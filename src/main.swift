import SwiftUI
import AppKit

// MARK: - Volumes

struct Vol: Identifiable {
    let id: URL
    let name: String
    let total: Int64
    let free: Int64
    let internalDisk: Bool
    let ident: String        // e.g. disk3s1
    let container: String    // e.g. disk3 (APFS container or the disk itself)
    let fs: String
    var used: Int64 { total - free }
}

struct Device: Identifiable {
    let id: String           // physical disk, e.g. disk1
    let name: String
    let size: Int64
    let bus: String
    let internalDisk: Bool
    let solid: Bool?
    var volumes: [Vol]
    var icon: String {
        if internalDisk { return "internaldrive" }
        return bus == "USB" ? "externaldrive.badge.plus" : "externaldrive"
    }
    var kind: String { solid == true ? "SSD" : (solid == false ? "HDD" : "Disk") }
}

func diskutilInfo(_ target: String) -> [String: Any] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    p.arguments = ["info", "-plist", target]
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [:] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
}

func wholeDisk(_ ident: String) -> String {
    // disk1s2 -> disk1
    guard let r = ident.range(of: "s[0-9]+$", options: .regularExpression) else { return ident }
    return String(ident[..<r.lowerBound])
}

func loadDevices() -> [Device] {
    let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey]
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                     options: [.skipHiddenVolumes]) ?? []
    var devices: [String: Device] = [:]
    for u in urls {
        guard let v = try? u.resourceValues(forKeys: Set(keys)),
              let total = v.volumeTotalCapacity, total > 0 else { continue }
        var free = v.volumeAvailableCapacityForImportantUsage ?? 0
        if free <= 0 { free = Int64(v.volumeAvailableCapacity ?? 0) }
        let info = diskutilInfo(u.path)
        let ident = info["DeviceIdentifier"] as? String ?? "?"
        let container = (info["APFSContainerReference"] as? String) ?? (info["ParentWholeDisk"] as? String) ?? wholeDisk(ident)
        var physical = (info["ParentWholeDisk"] as? String) ?? wholeDisk(ident)
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]],
           let st = stores.first?["APFSPhysicalStore"] as? String { physical = wholeDisk(st) }
        let isInternal = info["Internal"] as? Bool ?? (u.path == "/")
        let vol = Vol(id: u, name: v.volumeName ?? u.lastPathComponent, total: Int64(total), free: free,
                      internalDisk: isInternal, ident: ident, container: container,
                      fs: (info["FilesystemType"] as? String ?? "").uppercased())
        if devices[physical] == nil {
            let d = diskutilInfo(physical)
            var name = d["MediaName"] as? String ?? ""
            if name.isEmpty { name = d["IORegistryEntryName"] as? String ?? physical }
            devices[physical] = Device(id: physical, name: name,
                size: (d["TotalSize"] as? NSNumber)?.int64Value ?? 0,
                bus: d["BusProtocol"] as? String ?? info["BusProtocol"] as? String ?? "",
                internalDisk: d["Internal"] as? Bool ?? isInternal,
                solid: d["SolidState"] as? Bool ?? info["SolidState"] as? Bool, volumes: [])
        }
        devices[physical]!.volumes.append(vol)
    }
    return devices.values.map { d in var d = d; d.volumes.sort { $0.name < $1.name }; return d }
        .sorted { ($0.internalDisk ? 0 : 1, $0.id) < ($1.internalDisk ? 0 : 1, $1.id) }
}

func dlog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = FileHandle(forWritingAtPath: "/tmp/showvol.log") { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(toFile: "/tmp/showvol.log", atomically: false, encoding: .utf8) }
}

func volumeName(of path: String) -> String {
    let u = URL(fileURLWithPath: path)
    return (try? u.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "?"
}

let fmt: ByteCountFormatter = {
    let f = ByteCountFormatter(); f.countStyle = .file; return f
}()
func gb(_ n: Int64) -> String { fmt.string(fromByteCount: n) }

// MARK: - Search (Spotlight, subsequence fuzzy match on folder names)

struct Hit: Identifiable { let id = UUID(); let path: String; let name: String; let volume: String; let score: Int }

func fuzzyScore(_ query: String, _ name: String) -> Int? {
    let q = Array(query.lowercased()), n = Array(name.lowercased())
    var qi = 0, score = 0, lastMatch = -2
    for (i, c) in n.enumerated() where qi < q.count && c == q[qi] {
        score += (i == lastMatch + 1) ? 5 : 1          // consecutive bonus
        if i == 0 || !n[i-1].isLetter && !n[i-1].isNumber { score += 3 }  // word start
        lastMatch = i; qi += 1
    }
    guard qi == q.count else { return nil }
    if n.count == q.count { score += 20 }
    return score * 100 - n.count
}

final class Model: NSObject, ObservableObject {
    @Published var devices: [Device] = []
    var volumes: [Vol] { devices.flatMap { $0.volumes } }
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var hits: [Hit] = []
    @Published var searching = false
    private var debounce: DispatchWorkItem?
    private var proc: Process?
    private var gen = 0

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let d = loadDevices()
            DispatchQueue.main.async { self?.devices = d }
        }
    }

    private func scheduleSearch() {
        dlog("scheduleSearch q=\(query)")
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.runSearch() }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    private func runSearch() {
        proc?.terminate()
        gen += 1
        let myGen = gen
        let q = query.filter { !$0.isWhitespace }
        guard q.count >= 2 else { hits = []; searching = false; return }
        let pattern = "*" + q.map { String($0) }.joined(separator: "*") + "*"
        let esc = pattern.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemContentType == \"public.folder\" && kMDItemFSName == \"\(esc)\"cd"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        proc = p; searching = true
        dlog("run mdfind \(p.arguments ?? [])")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do { try p.run() } catch { dlog("run failed \(error)"); return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let paths = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            var out: [Hit] = []
            for path in paths {
                if path.hasPrefix("/System/") || path.hasPrefix("/Library/") || path.contains("/.") || path.contains(".app/") || path.contains("/node_modules/") { continue }
                let name = (path as NSString).lastPathComponent
                guard let s = fuzzyScore(q, name) else { continue }
                out.append(Hit(path: path, name: name, volume: volumeName(of: path), score: s))
            }
            dlog("mdfind paths=\(paths.count) kept=\(out.count) bytes=\(data.count)")
            let top = Array(out.sorted { $0.score > $1.score }.prefix(100))
            DispatchQueue.main.async {
                guard let self = self, self.gen == myGen else { return }
                self.hits = top; self.searching = false
            }
        }
    }
}

// MARK: - UI

struct VolRow: View {
    let v: Vol
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(v.name).fontWeight(.medium)
                Text(v.ident).font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("\(gb(v.free)) free of \(gb(v.total))").font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: Double(v.used), total: Double(v.total))
                .tint(Double(v.free) / Double(v.total) < 0.1 ? .red : .accentColor)
        }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(v.id) }
    }
}

struct DeviceView: View {
    let d: Device
    var color: Color { d.internalDisk ? .blue : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: d.icon).font(.title2).foregroundColor(color).frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.name).fontWeight(.semibold)
                    Text([d.internalDisk ? "Internal" : "External", d.bus, d.kind, gb(d.size), d.id]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(d.volumes) { VolRow(v: $0) }
                if Set(d.volumes.map { $0.container }).count < d.volumes.count {
                    Text("Volumes in the same APFS container share free space")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.leading, 36)
        }
    }
}

struct ContentView: View {
    @ObservedObject var m: Model
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(m.devices) { DeviceView(d: $0) }
            Divider()
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Find folder (fuzzy)…", text: $m.query)
                    .textFieldStyle(.plain).focused($focused)
                if m.searching { ProgressView().controlSize(.small) }
            }
            if !m.hits.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(m.hits) { h in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(h.name).fontWeight(.medium)
                                    Spacer()
                                    let isInt = m.volumes.first { $0.name == h.volume }?.internalDisk ?? true
                                    Label(h.volume, systemImage: isInt ? "internaldrive" : "externaldrive")
                                        .font(.caption).padding(.horizontal, 6)
                                        .background(Capsule().fill((isInt ? Color.blue : Color.orange).opacity(0.2)))
                                }
                                Text(h.path).font(.caption2).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: h.path)]) }
                            .contextMenu {
                                Button("Copy path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(h.path, forType: .string)
                                }
                            }
                        }
                    }
                }.frame(maxHeight: 280)
            } else if !m.query.isEmpty && !m.searching && m.query.count >= 2 {
                Text("No matching folders").font(.caption).foregroundColor(.secondary)
            }
            Divider()
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(12).frame(width: 380)
        .onAppear { m.refresh(); focused = true }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var item: NSStatusItem!
    let pop = NSPopover()

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let vIcon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3.5, y: 14)); p.line(to: NSPoint(x: 9, y: 4)); p.line(to: NSPoint(x: 14.5, y: 14))
            p.lineWidth = 3; p.lineCapStyle = .round; p.lineJoinStyle = .round
            NSColor.black.setStroke(); p.stroke()
            return true
        }
        vIcon.isTemplate = true
        vIcon.accessibilityDescription = "Volumes"
        item.button?.image = vIcon
        item.button?.action = #selector(toggle)
        item.button?.target = self
        pop.behavior = .transient
        let hc = NSHostingController(rootView: ContentView(m: model))
        hc.sizingOptions = [.preferredContentSize]
        pop.contentViewController = hc
        model.refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.model.refresh() }
        }
    }

    @objc func toggle() {
        guard let b = item.button else { return }
        if pop.isShown { pop.performClose(nil) } else {
            model.refresh()
            pop.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
