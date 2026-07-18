//
//  FamilyPickerView.swift
//  ParentLock
//
//  Thin wrapper around FamilyActivityPicker with a save/cancel toolbar.
//

import SwiftUI
import FamilyControls

struct FamilyPickerSheet: View {
    let title: LocalizedStringKey
    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FamilyActivitySelection()

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $draft)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            selection = draft
                            dismiss()
                        }
                        .bold()
                    }
                }
        }
        .onAppear { draft = selection }
    }
}
