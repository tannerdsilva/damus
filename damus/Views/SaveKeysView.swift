//
//  SaveKeysView.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import SwiftUI

struct SaveKeysView: View {
    let account: CreateAccountModel
    let pool: RelayPool = RelayPool()
    @State var is_done: Bool = false
    @State var pub_copied: Bool = false
    @State var priv_copied: Bool = false
    @State var loading: Bool = false
    @State var error: String? = nil

    @FocusState var pubkey_focused: Bool
    @FocusState var privkey_focused: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            DamusGradient()
            
            VStack(alignment: .center) {
                Text("Welcome, \(account.rendered_name)!", comment: "Text to welcome user.")
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("Before we get started, you'll need to save your account info, otherwise you won't be able to login in the future if you ever uninstall Damus.", comment: "Reminder to user that they should save their account information.")
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("Public Key", comment: "Label to indicate that text below is the user's public key used by others to uniquely refer to the user.")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                Text("This is your account ID, you can give this to your friends so that they can follow you. Tap to copy.", comment: "Label to describe that a public key is the user's account ID and what they can do with it.")
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                SaveKeyView(text: account.pubkey_bech32, textContentType: .username, is_copied: $pub_copied, focus: $pubkey_focused)
                    .padding(.bottom, 10)
                
                if pub_copied {
                    Text("Private Key", comment: "Label to indicate that the text below is the user's private key used by only the user themself as a secret to login to access their account.")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    
                    Text("This is your secret account key. You need this to access your account. Don't share this with anyone! Save it in a password manager and keep it safe!", comment: "Label to describe that a private key is the user's secret account key and what they should do with it.")
                        .foregroundColor(.white)
                        .padding(.bottom, 10)
                    
                    SaveKeyView(text: account.privkey_bech32, textContentType: .newPassword, is_copied: $priv_copied, focus: $privkey_focused)
                        .padding(.bottom, 10)
                }
                
                if pub_copied && priv_copied {
                    if loading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if let err = error {
                        Text("Error: \(err)", comment: "Error message indicating why saving keys failed.")
                            .foregroundColor(.red)
                        DamusWhiteButton(NSLocalizedString("Retry", comment: "Button to retry completing account creation after an error occurred.")) {
                            complete_account_creation(account)
                        }
                    } else {
                        DamusWhiteButton(NSLocalizedString("Let's go!", comment: "Button to complete account creation and start using the app.")) {
                            complete_account_creation(account)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
        .onAppear {
            // Hack to force keyboard to show up for a short moment and then hiding it to register password autofill flow.
            pubkey_focused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pubkey_focused = false
            }
        }
    }
    
    func complete_account_creation(_ account: CreateAccountModel) {
        let bootstrap_relays = load_bootstrap_relays(pubkey: account.pubkey)
        for relay in bootstrap_relays {
            add_rw_relay(self.pool, relay)
        }

        self.pool.register_handler(sub_id: "signup", handler: handle_event)
        
        self.loading = true
        
        self.pool.connect()
    }
    
    func handle_event(relay: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event(let wsev):
            switch wsev {
            case .connected:
                let metadata = create_account_to_metadata(account)
                let metadata_ev = make_metadata_event(keypair: account.keypair, metadata: metadata)
                let contacts_ev = make_first_contact_event(keypair: account.keypair)
                
                if let metadata_ev {
                    self.pool.send(.event(metadata_ev))
                }
                if let contacts_ev {
                    self.pool.send(.event(contacts_ev))
                }
                
                do {
                    try save_keypair(pubkey: account.pubkey, privkey: account.privkey)
                    notify(.login, account.keypair)
                } catch {
                    self.error = "Failed to save keys"
                }
                
            case .error(let err):
                self.loading = false
                self.error = String(describing: err)
            default:
                break
            }
        case .nostr_event(let resp):
            switch resp {
            case .notice(let msg):
                // TODO handle message
                self.loading = false
                self.error = msg
                print(msg)
            case .event:
                print("event in signup?")
            case .eose:
                break
            case .ok:
                break
            }
        }
    }
}

struct SaveKeyView: View {
    let text: String
    let textContentType: UITextContentType
    @Binding var is_copied: Bool
    var focus: FocusState<Bool>.Binding
    
    func copy_text() {
        UIPasteboard.general.string = text
        is_copied = true
    }
    
    var body: some View {
        HStack {
            Spacer()
            VStack {
                spacerBlock(width: 0, height: 0)
                Button(action: copy_text) {
                    Label("", systemImage: is_copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundColor(is_copied ? .green : .white)
                        .background {
                            if is_copied {
                                Circle()
                                    .foregroundColor(.white)
                                    .frame(width: 25, height: 25, alignment: .center)
                                    .padding(.leading, -8)
                                    .padding(.top, 1)
                            } else {
                                EmptyView()
                            }
                        }
                }
            }

            TextField("", text: .constant(text))
                .padding(5)
                .background {
                    RoundedRectangle(cornerRadius: 4.0).opacity(0.2)
                }
                .textSelection(.enabled)
                .font(.callout.monospaced())
                .foregroundColor(.white)
                .onTapGesture {
                    copy_text()
                    // Hack to force keyboard to hide. Showing keyboard on text field is necessary to register password autofill flow but the text itself should not be modified.
                    DispatchQueue.main.async {
                        end_editing()
                    }
                }
                .textContentType(textContentType)
                .deleteDisabled(true)
                .focused(focus)
            
            spacerBlock(width: 0, height: 0) /// set a 'width' > 0 here to vary key Text's aspect ratio
        }
    }
    
    @ViewBuilder private func spacerBlock(width: CGFloat, height: CGFloat) -> some View {
        Color.orange.opacity(1)
            .frame(width: width, height: height)
    }
}

struct SaveKeysView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CreateAccountModel(real: "William", nick: "jb55", about: "I'm me")
        SaveKeysView(account: model)
    }
}

func create_account_to_metadata(_ model: CreateAccountModel) -> Profile {
    return Profile(name: model.nick_name, display_name: model.real_name, about: model.about, picture: model.profile_image, banner: nil, website: nil, lud06: nil, lud16: nil, nip05: nil)
}
