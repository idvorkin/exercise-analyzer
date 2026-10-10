// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 070 (#231): what the iCloud sync is doing, live, for the day the sets do not come: this device, the
//  container and account, the metadata query's counts, the last mirror and read passes, the devices seen and the
//  last twenty sync events, with a Sync now button. Under the ⋯ menu as "Sync status".

import SwiftUI

struct SyncStatusView: View {
  @ObservedObject var sync: SyncStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        let s = sync.status
        Section("This device") {
          row("Device id", s.deviceID)
          row("iCloud account", s.accountSignedIn ? "signed in" : "none")
          row("Container", s.containerAvailable ? "available" : "not available")
          if !s.containerPath.isEmpty {
            Text(s.containerPath).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }
        Section("iCloud query") {
          row("State", s.query.state)
          row("Results", "\(s.query.results)")
          row("Downloaded", "\(s.query.downloaded)")
          row("Not downloaded", "\(s.query.notDownloaded)")
          row("Downloading", "\(s.query.downloading)")
          row("Download errors", "\(s.query.errors)")
          if !s.query.lastError.isEmpty { Text(s.query.lastError).font(.caption).foregroundStyle(.red) }
        }
        Section("This device's files going up") {
          row("Uploaded", "\(s.query.uploaded)")
          row("Uploading", "\(s.query.uploading)")
          row("Not uploaded", "\(s.query.notUploaded)")
          row("Upload errors", "\(s.query.uploadErrors)")
          if !s.query.lastUploadError.isEmpty { Text(s.query.lastUploadError).font(.caption).foregroundStyle(.red) }
        }
        Section("Passes") {
          row("Mirrored", "\(s.mirrored) rows")
          pass("Last mirror", s.lastMirror)
          pass("Last read", s.lastRead)
        }
        Section("Devices seen in the container") {
          if s.devices.isEmpty {
            Text("none yet").foregroundStyle(.secondary)
          }
          ForEach(s.devices) { device in
            VStack(alignment: .leading, spacing: 2) {
              Text(device.id == s.deviceID ? "this device" : device.id).font(.callout.monospaced())
              Text("\(device.sets) sets, \(device.workouts) workouts").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Section("Last sync events") {
          if s.events.isEmpty {
            Text("none yet").foregroundStyle(.secondary)
          }
          ForEach(s.events) { event in
            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Text(event.type).font(.callout.monospaced().bold())
                Spacer()
                Text(event.at, style: .time).font(.caption).foregroundStyle(.secondary)
              }
              Text(event.fields).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
          }
        }
      }
      .navigationTitle("Sync status")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            sync.syncNow()
          } label: {
            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
          }
        }
      }
    }
  }

  private func row(_ name: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(name)
      Spacer()
      Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing).textSelection(.enabled)
    }
  }

  private func pass(_ name: String, _ pass: SyncStatus.Pass) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(name)
        Spacer()
        if let at = pass.at { Text(at, style: .time).foregroundStyle(.secondary) }
      }
      Text(pass.summary).font(.caption).foregroundStyle(.secondary)
    }
  }
}
