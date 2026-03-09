//
//  PromptEditor.swift
//  DayArc
//
//  Reusable UI component for editing prompts
//

import SwiftUI

struct PromptEditor: View {
    let context: PromptContext
    @State private var customPrompt: String
    @State private var showingEditor = false
    
    init(context: PromptContext) {
        self.context = context
        _customPrompt = State(initialValue: PromptManager.shared.getCustomPrompt(for: context) ?? "")
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.displayName)
                    .font(.headline)
                Text(context.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !customPrompt.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .help("Custom prompt active")
            }
            
            Button("Edit") {
                showingEditor = true
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditor) {
            PromptEditorSheet(context: context, customPrompt: $customPrompt)
        }
    }
}

struct PromptEditorSheet: View {
    let context: PromptContext
    @Binding var customPrompt: String
    @Environment(\.dismiss) var dismiss
    
    @State private var workingCopy: String
    
    init(context: PromptContext, customPrompt: Binding<String>) {
        self.context = context
        self._customPrompt = customPrompt
        self._workingCopy = State(initialValue: customPrompt.wrappedValue)
    }
    
    var characterCount: Int {
        workingCopy.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
    
    var isOverLimit: Bool {
        characterCount > PromptManager.maxCustomPromptLength
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Edit \(context.displayName)")
                        .font(.title2)
                        .bold()
                    Text(context.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Default Prompt (읽기 전용)
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Prompt")
                    .font(.headline)
                Text("This is the built-in prompt. Your custom addition will be appended to this.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    Text(PromptManager.shared.getDefaultPrompt(for: context))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
                .frame(height: 200)
            }
            
            // Custom Addition (편집 가능)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your Custom Addition")
                        .font(.headline)
                    Spacer()
                    Text("\(characterCount) / \(PromptManager.maxCustomPromptLength)")
                        .font(.caption)
                        .foregroundColor(isOverLimit ? .red : .secondary)
                }
                
                Text("Add extra instructions or override default behavior (max 2,000 characters)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $workingCopy)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .border(isOverLimit ? Color.red : Color.gray.opacity(0.3), width: 1)
                    .cornerRadius(6)
                
                if isOverLimit {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Exceeds 2,000 character limit. Will be truncated on save.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("Reset to Default") {
                    workingCopy = ""
                }
                .disabled(workingCopy.isEmpty)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    PromptManager.shared.setCustomPrompt(
                        for: context,
                        custom: workingCopy.isEmpty ? nil : workingCopy
                    )
                    customPrompt = PromptManager.shared.getCustomPrompt(for: context) ?? ""
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700, height: 650)
    }
}

// MARK: - Preview

#Preview {
    PromptEditor(context: .activityCardTitle)
        .padding()
}
