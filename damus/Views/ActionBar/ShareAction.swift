//
//  ShareAction.swift
//  damus
//
//  Created by eric on 3/8/23.
//

import SwiftUI

struct ShareAction: View {
    let event: NostrEvent
    let bookmarks: BookmarksManager
    @State private var isBookmarked: Bool = false

    @Binding var show_share: Bool
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    init(event: NostrEvent, bookmarks: BookmarksManager, show_share: Binding<Bool>) {
        let bookmarked = bookmarks.isBookmarked(event)
        self._isBookmarked = State(initialValue: bookmarked)
        
        self.bookmarks = bookmarks
        self.event = event
        self._show_share = show_share
    }
    
    var body: some View {
        
        VStack {
            Text("Share Note", comment: "Title text to indicate that the buttons below are meant to be used to share a note with others.")
                .padding()
                .font(.system(size: 17, weight: .bold))
            
            Spacer()

            HStack(alignment: .top, spacing: 25) {
                
                ShareActionButton(img: "link", text: NSLocalizedString("Copy Link", comment: "Button to copy link to note")) {
                    UIPasteboard.general.string = "https://damus.io/" + (bech32_note_id(event.id) ?? event.id)
                }
                
                let bookmarkImg = isBookmarked ? "bookmark.slash" : "bookmark"
                let bookmarkTxt = isBookmarked ? NSLocalizedString("Remove Bookmark", comment: "Button text to remove bookmark from a note.") : NSLocalizedString("Add Bookmark", comment: "Button text to add bookmark to a note.")
                let boomarkCol = isBookmarked ? Color(.red) : nil
                ShareActionButton(img: bookmarkImg, text: bookmarkTxt, col: boomarkCol) {
                    dismiss()
                    self.bookmarks.updateBookmark(event)
                    isBookmarked = self.bookmarks.isBookmarked(event)
                }
                
                ShareActionButton(img: "globe", text: NSLocalizedString("Broadcast", comment: "Button to broadcast note to all your relays")) {
                    dismiss()
                    NotificationCenter.default.post(name: .broadcast_event, object: event)
                }
                
                ShareActionButton(img: "square.and.arrow.up", text: NSLocalizedString("Share Via...", comment: "Button to present iOS share sheet")) {
                    show_share = true
                    dismiss()
                }
                
            }
            
            Spacer()
            
            HStack {
                BigButton(NSLocalizedString("Cancel", comment: "Button to cancel a repost.")) {
                    dismiss()
                }
            }
        }
    }
}

