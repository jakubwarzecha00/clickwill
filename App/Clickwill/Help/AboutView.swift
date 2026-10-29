import SwiftUI
import AppKit

/// The "About" panel: the legal text of a free app.
/// The license section and the License button are the GPL's "Appropriate Legal
/// Notices" (section 5d): copyright, no warranty, the right to convey, the license text.
/// The name, version and author details come from `AboutFacts`.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    /// The bundled text shown in a sheet: the license or the third-party notices.
    @State private var document: BundledDocument?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.sep)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    license
                    independence
                    doesAndDoesNot
                    yourContent
                    if AboutFacts.stage != nil { testVersion }
                    warranty
                    acknowledgements
                }
                .padding(EdgeInsets(top: 20, leading: 26, bottom: 26, trailing: 26))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Theme.sep)
            HStack {
                Button("License") { document = .license }
                Button("Third-party notices") { document = .notices }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        }
        .frame(width: 620, height: 640)
        .background(Theme.bg)
        .foregroundStyle(Theme.fg)
        .sheet(item: $document) { TextDocumentView(document: $0) }
    }

    // MARK: 1. Name and version

    private var header: some View {
        HStack(spacing: 16) {
            appIcon.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(AboutFacts.appName).font(.theme(.title, weight: .bold))
                Text("Version \(AboutFacts.version)\(AboutFacts.stage.map { " · \($0)" } ?? "")").font(.theme(.callout)).foregroundStyle(Theme.f2)
                Text("An independent library editor for iPod classic and iPod nano.").font(.theme(.body)).foregroundStyle(Theme.f2)
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 22, leading: 26, bottom: 18, trailing: 26))
    }

    @ViewBuilder private var appIcon: some View {
        Image(nsImage: NSApp.applicationIconImage).resizable()
    }

    // MARK: 2. License

    private var license: some View {
        section("License") {
            para("\(AboutFacts.appName) is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3, as published by the Free Software Foundation.")
            para("It is distributed in the hope that it will be useful, but without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose. Choose License below to read the full terms.")
            Link("Source code on GitHub", destination: AboutFacts.sourceURL)
                .font(.theme(.body))
                .foregroundStyle(Color.accentColor)  // the window imposes Theme.fg, a link has the accent color
        }
    }

    // MARK: 3. Independence and trademarks

    private var independence: some View {
        section("Independence and trademarks") {
            para("\(AboutFacts.appName) is an independent product. It is not affiliated with, endorsed by, sponsored by, or otherwise connected to Apple Inc.")
            para("iPod, iPod classic, iPod nano, Click Wheel, Cover Flow, iTunes, Apple Music, Mac, and macOS are trademarks of Apple Inc., registered in the U.S. and other countries. These names are used here solely to identify the devices and software this app works with, in a purely descriptive manner, and not to suggest any endorsement or association.")
            para("This app is signed with an Apple Developer ID and notarized by Apple. Notarization is an automated check for malicious software; it is not a review, approval, or endorsement of the app by Apple.")
        }
    }

    // MARK: 4. What this app does - and does not do

    private var doesAndDoesNot: some View {
        section("What this app does, and does not do") {
            para("This app reads and edits the music library on an iPod classic or iPod nano that you own and have connected to your Mac as an ordinary USB mass-storage volume.")
            subhead("What it does")
            bullet("Reads the library database (iTunesDB) and artwork files that already exist on the device, in their documented, plain-file form.")
            bullet("Lets you add songs, change the order in which albums and songs appear, change album artwork, remove songs and their audio files, and merge the device's own play statistics back into the library.")
            bullet("Writes only to those data files and to the audio files you add or remove, and only when you explicitly choose \u{201C}Write to iPod\u{201D}. Every write is preceded by a full backup of the library files and followed by a read-back verification.")
            subhead("What it does not do")
            bullet("It does not modify, patch, replace, or interact with the device's firmware, bootloader, or operating system.")
            bullet("It does not circumvent, disable, or weaken any technical protection measure, encryption, or digital-rights-management mechanism. It does not decrypt, copy, or make available any protected content. Songs purchased with DRM remain as they are.")
            bullet("It does not exploit any vulnerability, does not require a jailbreak, and does not change the device's security posture in any way. The device continues to work exactly as it did with Apple's own software.")
            bullet("It does not modify Apple Music, iTunes, macOS, or any other Apple software, and it does not run in the background. It only warns you when Apple Music is open, because Apple Music may overwrite the library on the next connection.")
            bullet("It does not collect analytics. It goes online only to check for updates and, when you click Look Up Online for a CD, to ask MusicBrainz for that disc's song names and cover. Your library never leaves your computer.")
        }
    }

    // MARK: 5. Your content and your device

    private var yourContent: some View {
        section("Your content and your device") {
            para("You are responsible for the content on your device and for having the right to use it. This app helps you organize files you already have; it does not obtain music for you and does not enable sharing it with others.")
            para("Editing a device's library carries some risk. This app makes a backup before every write and verifies what it wrote, but no software is perfect. Keep your own backup of music you care about. Restoring the device with Apple's own tools returns it to a clean, supported state at any time.")
        }
    }

    // MARK: 6. Test version (alpha, beta)

    private var testVersion: some View {
        section("About \(AboutFacts.thisVersion)") {
            para("This is a test version of \(AboutFacts.appName), free of charge. It writes to the iPod classic and the iPod nano (2nd to 4th generation); other iPods open read-only while support for them is in active development.")
            if let email = AboutFacts.supportEmail {
                para("To report a problem, choose Help › Copy Diagnostic Report, add a description of what happened, and send it to \(email).")
            } else {
                para("To report a problem, choose Send Feedback in the sidebar or in the Help menu, describe what happened, and send it together with the diagnostic report.")
            }
        }
    }

    // MARK: 7. Warranty and liability

    private var warranty: some View {
        section("Warranty and liability") {
            para("This app is provided free of charge. To the fullest extent permitted by applicable law, it is provided \u{201C}as is\u{201D}, without warranty of any kind.")
            para("Your statutory rights are not affected. If you are a consumer, nothing in this notice limits any right you have under the laws of your country, including rights concerning conformity of digital content.")
        }
    }

    // MARK: 8. Acknowledgements

    private var acknowledgements: some View {
        section("Acknowledgements") {
            para("The structure of the iPod library database has been documented by the open-source community over many years (notably the libgpod project and the iPodLinux wiki). This app contains its own, independently written implementation and includes no Apple code.")
            para("The integrity checksum the device verifies (hash58) is implemented from the algorithm published by the libgpod project in 2007; its BSD license notice is reproduced in full under \u{201C}Third-party notices\u{201D}. This checksum protects no content and restricts no access: the same audio files play with or without it.")
            Text("Copyright © \(AboutFacts.year) \(AboutFacts.author). Licensed under the GNU General Public License, version 3.")
                .font(.theme(.footnote)).foregroundStyle(Theme.f2).padding(.top, 4)
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.theme(.heading, weight: .semibold))
            content()
        }
    }

    private func subhead(_ text: String) -> some View {
        Text(text).font(.theme(.body, weight: .semibold)).padding(.top, 2)
    }

    private func para(_ text: String) -> some View {
        Text(text).font(.theme(.body)).foregroundStyle(Theme.fg.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.theme(.body)).foregroundStyle(Theme.f2)
            para(text)
        }
    }
}

/// A text file bundled with the app, shown from the About panel.
enum BundledDocument: String, Identifiable {
    case license, notices
    var id: String { rawValue }

    var title: String { self == .license ? "GNU General Public License" : "Third-Party Notices" }
    var text: String { self == .license ? AboutFacts.license : AboutFacts.thirdPartyNotices }
}

struct TextDocumentView: View {
    let document: BundledDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title).font(.theme(.heading, weight: .semibold))
                Spacer()
            }
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 12, trailing: 22))
            Divider().overlay(Theme.sep)
            ScrollView {
                Text(document.text)
                    .font(.theme(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.fg.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
            }
            Divider().overlay(Theme.sep)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        }
        .frame(width: 620, height: 560)
        .background(Theme.bg)
        .foregroundStyle(Theme.fg)
    }
}
