//
//  PromptManager.swift
//  DayArc
//
//  Centralized prompt management for all AI features
//

import Foundation

// MARK: - Prompt Context

enum PromptContext: String, CaseIterable {
    case activityCardTitle = "activity_card_title"
    case activityCardSummary = "activity_card_summary"
    case activityCardDetailed = "activity_card_detailed"
    case videoTranscription = "video_transcription"
    case dailyReportAnalysis = "daily_report"
    case weeklyReportAnalysis = "weekly_report"
    case monthlyReportAnalysis = "monthly_report"
    case timelineSummary = "timeline_summary"
    
    var displayName: String {
        switch self {
        case .activityCardTitle:
            return "Activity Card Title"
        case .activityCardSummary:
            return "Activity Card Summary"
        case .activityCardDetailed:
            return "Activity Card Detailed Summary"
        case .videoTranscription:
            return "Video Transcription"
        case .dailyReportAnalysis:
            return "Daily Report Analysis"
        case .weeklyReportAnalysis:
            return "Weekly Report Analysis"
        case .monthlyReportAnalysis:
            return "Monthly Report Analysis"
        case .timelineSummary:
            return "Timeline Summary"
        }
    }
    
    var description: String {
        switch self {
        case .activityCardTitle:
            return "Guidelines for generating activity card titles"
        case .activityCardSummary:
            return "Guidelines for generating concise activity summaries"
        case .activityCardDetailed:
            return "Guidelines for generating detailed timeline breakdowns"
        case .videoTranscription:
            return "Instructions for analyzing screen recordings"
        case .dailyReportAnalysis:
            return "Analysis style for daily reports"
        case .weeklyReportAnalysis:
            return "Analysis style for weekly reports"
        case .monthlyReportAnalysis:
            return "Analysis style for monthly reports"
        case .timelineSummary:
            return "Instructions for timeline group summaries"
        }
    }
    
    var category: String {
        switch self {
        case .activityCardTitle, .activityCardSummary, .activityCardDetailed:
            return "Activity Cards"
        case .videoTranscription:
            return "Video Analysis"
        case .dailyReportAnalysis, .weeklyReportAnalysis, .monthlyReportAnalysis, .timelineSummary:
            return "Report Generation"
        }
    }
}

// MARK: - Prompt Template

struct PromptTemplate: Codable {
    var defaultPrompt: String
    var customPrompt: String?  // nil = use default only
    
    /// Combines default and custom prompts
    var resolvedPrompt: String {
        guard let custom = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !custom.isEmpty else {
            return defaultPrompt
        }
        return defaultPrompt + "\n\n" + custom
    }
}

// MARK: - Prompt Manager

class PromptManager {
    static let shared = PromptManager()
    
    private let store = UserDefaults.standard
    private let keyPrefix = "prompt_"
    
    /// Maximum length for custom prompt additions (for performance)
    static let maxCustomPromptLength = 2000
    
    private init() {
        // Run migration once on first access
        migrateFromGeminiPromptPreferences()
    }
    
    // MARK: - Public API
    
    /// Get resolved prompt (default + custom)
    func getPrompt(for context: PromptContext) -> String {
        let template = loadTemplate(for: context)
        return template.resolvedPrompt
    }
    
    /// Set custom prompt addition (max 2000 characters for performance)
    func setCustomPrompt(for context: PromptContext, custom: String?) {
        var template = loadTemplate(for: context)
        
        // Enforce character limit
        if let customText = custom, !customText.isEmpty {
            let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > Self.maxCustomPromptLength {
                Logger.shared.warning("Custom prompt exceeds \(Self.maxCustomPromptLength) character limit. Truncating.", source: "PromptManager")
                template.customPrompt = String(trimmed.prefix(Self.maxCustomPromptLength))
            } else {
                template.customPrompt = trimmed
            }
        } else {
            template.customPrompt = custom
        }
        
        saveTemplate(template, for: context)
    }
    
    /// Get only the custom prompt (for UI display)
    func getCustomPrompt(for context: PromptContext) -> String? {
        let template = loadTemplate(for: context)
        return template.customPrompt
    }
    
    /// Get only the default prompt (for UI display)
    func getDefaultPrompt(for context: PromptContext) -> String {
        return PromptDefaults.defaultPrompt(for: context)
    }
    
    /// Reset a specific prompt to default
    func resetPrompt(for context: PromptContext) {
        let key = keyPrefix + context.rawValue
        store.removeObject(forKey: key)
    }
    
    /// Reset all prompts to defaults
    func resetAll() {
        for context in PromptContext.allCases {
            resetPrompt(for: context)
        }
    }
    
    // MARK: - Private Helpers
    
    private func loadTemplate(for context: PromptContext) -> PromptTemplate {
        let key = keyPrefix + context.rawValue
        
        if let data = store.data(forKey: key),
           let template = try? JSONDecoder().decode(PromptTemplate.self, from: data) {
            return template
        }
        
        // Return default template
        return PromptTemplate(
            defaultPrompt: PromptDefaults.defaultPrompt(for: context),
            customPrompt: nil
        )
    }
    
    private func saveTemplate(_ template: PromptTemplate, for context: PromptContext) {
        let key = keyPrefix + context.rawValue
        if let data = try? JSONEncoder().encode(template) {
            store.set(data, forKey: key)
        }
    }
    
    // MARK: - Migration
    
    private func migrateFromGeminiPromptPreferences() {
        let migrationKey = "prompt_migration_completed"
        guard !store.bool(forKey: migrationKey) else { return }
        
        let oldOverrides = GeminiPromptPreferences.load()
        
        // Migrate title
        if let titleBlock = oldOverrides.titleBlock,
           !titleBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setCustomPrompt(for: .activityCardTitle, custom: titleBlock)
        }
        
        // Migrate summary
        if let summaryBlock = oldOverrides.summaryBlock,
           !summaryBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setCustomPrompt(for: .activityCardSummary, custom: summaryBlock)
        }
        
        // Migrate detailed
        if let detailedBlock = oldOverrides.detailedBlock,
           !detailedBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setCustomPrompt(for: .activityCardDetailed, custom: detailedBlock)
        }
        
        store.set(true, forKey: migrationKey)
        Logger.shared.info("✅ Migrated prompts from GeminiPromptPreferences to PromptManager", source: "PromptManager")
    }
}

// MARK: - Default Prompts

enum PromptDefaults {
    static func defaultPrompt(for context: PromptContext) -> String {
        switch context {
        case .activityCardTitle:
            return titleBlock
        case .activityCardSummary:
            return summaryBlock
        case .activityCardDetailed:
            return detailedSummaryBlock
        case .videoTranscription:
            return videoTranscriptionBlock
        case .dailyReportAnalysis, .weeklyReportAnalysis, .monthlyReportAnalysis:
            return reportAnalysisBlock
        case .timelineSummary:
            return timelineSummaryBlock
        }
    }
    
    // Activity Card - Title (from GeminiPromptDefaults)
    static let titleBlock = """
Title guidelines:
Write titles like you're texting a friend about what you did. Natural, conversational, direct, specific.

Rules:
- Be specific and clear (not creative or vague)
- Keep it short - aim for 5-10 words
- Don't reference other cards or assume context
- Include main activity + distraction if relevant
- Include specific app/tool names, not generic activities
- Use specific verbs: "Debugged Python" not "Worked on project"

Good examples:
- "Debugged auth flow in React"
- "Excel budget analysis for Q4 report"
- "Zoom call with design team"
- "Booked flights on Expedia for Denver trip"
- "Watched Succession finale on HBO"
- "Grocery list and meal prep research"
- "Reddit rabbit hole about conspiracy theories"
- "Random YouTube shorts for 30 minutes"
- "Instagram reels and Twitter scrolling"

Bad examples:
- "Early morning digital drift" (too vague/poetic)
- "Fell down a rabbit hole after lunch" (too long, assumes context)
- "Extended Browsing Session" (too formal)
- "Random browsing and activities" (not specific)
- "Continuing from earlier" (references other cards)
- "Worked on DayFlow project" (too generic - what specifically?)
- "Browsed social media and shopped" (which platforms? for what?)
- "Refined UI and prompts" (which tools? what UI?)
"""
    
    // Activity Card - Summary (from GeminiPromptDefaults)
    static let summaryBlock = """
Summary guidelines:
Write brief factual summaries optimized for quick scanning. First person perspective without "I".

Critical rules - NEVER:
- Use third person ("The session", "The work")
- Assume future actions, mental states, or unverifiable details
- Add filler phrases like "kicked off", "dove into", "started with", "began by"
- Write more than 2-3 short sentences
- Repeat the same phrases across different summaries

Style guidelines:
- State what happened directly - no lead-ins
- List activities and tools concisely
- Mention major interruptions or context switches briefly
- Keep technical terms simple

Content rules:
- Maximum 2-3 sentences
- Just the facts: what you did, which tools/projects, major blockers
- Include specific names (apps, tools, sites) not generic terms
- Note pattern interruptions without elaborating

Good examples:
"Refactored the user auth module in React, added OAuth support. Debugged CORS issues with the backend API for an hour. Posted question on Stack Overflow when the fix wasn't working."

"Designed new landing page mockups in Figma. Exported assets and started implementing in Next.js before getting pulled into a client meeting that ran long."

"Researched competitors' pricing models across SaaS platforms. Built comparison spreadsheet and wrote up recommendations. Got sidetracked reading an article about pricing psychology."

"Configured CI/CD pipeline in GitHub Actions. Tests kept failing on the build step, turned out to be a Node version mismatch. Fixed it and deployed to staging."

Bad examples:
"Kicked off the morning by diving into some design work before transitioning to development tasks. The session was quite productive overall."
(Too vague, unnecessary transitions, says nothing specific)

"Started with refactoring the authentication system before moving on to debugging some issues that came up. Ended up spending time researching solutions online."
(Wordy, lacks specifics, could be half the length)

"Began by reviewing the codebase and then dove deep into implementing new features. The work involved multiple context switches between different parts of the application."
(All filler, no actual information)
"""
    
    // Activity Card - Detailed Summary (from GeminiPromptDefaults)
    static let detailedSummaryBlock = """
Detailed Summary guidelines:
The detailedSummary field must provide a minute-by-minute timeline of activities within the card's duration. This is a granular activity log showing every context switch and time spent.

Format rules:
- Use exact time ranges in "H:MM AM/PM - H:MM AM/PM" format
- One activity per line
- Keep descriptions short and specific (2-5 words typical)
- Include app/tool names
- Show ALL context switches, even brief ones
- Order chronologically
- No narrative text, just the timeline
- IMPORTANT: Add markdown line breaks (double newline) between distinct time periods or activity groups for better readability

Structure:
"[startTime] - [endTime] [specific activity in tool/app]"

Examples of good detailedSummary format:
"7:00 AM - 7:30 AM writing notion doc
7:30 AM - 7:35 AM responding to slack DMs

7:35 AM - 7:38 AM scrolling x.com
7:38 AM - 7:45 AM writing notion doc

7:45 AM - 8:05 AM coding in Cursor and iterm
8:05 AM - 8:08 AM checking gmail

8:08 AM - 8:25 AM debugging in VS Code
8:25 AM - 8:30 AM Stack Overflow research"

"2:15 PM - 2:18 PM opened Figma
2:18 PM - 2:45 PM designing landing page mockups

2:45 PM - 2:47 PM quick Twitter check
2:47 PM - 3:10 PM continued Figma designs

3:10 PM - 3:15 PM exporting assets
3:15 PM - 3:30 PM implementing in Next.js"

Bad examples (DO NOT DO):
- "Worked on various tasks throughout the session" (not granular)
- "Started with email, then moved to coding" (narrative, not timeline)
- "15 minutes on email, 30 minutes coding" (duration-based, not time-based)
- Missing specific times or tools
- No line breaks between activity groups (harder to read)
"""
    
    // Video Transcription
    static let videoTranscriptionBlock = """
Transcribe this screen recording video and identify what activities the user was doing. Focus on:
- Application names and window titles
- Visible text on screen
- User interactions
- Time spent on each activity

Provide structured observations with timestamps and app details.
"""
    
    // Report Analysis (Daily/Weekly/Monthly)
    static let reportAnalysisBlock = """
Please analyze the following activity log and provide:
1. A concise title summarizing the period
2. A brief summary of accomplishments and patterns
3. Key insights about productivity, focus, and time usage
4. Specific recommendations for improvement

Focus on actionable insights and patterns rather than just listing activities.
"""
    
    // Timeline Summary (from SchedulerManager:754-771)
    static let timelineSummaryBlock = """
Please analyze the following activity log and provide:
1. A concise title (max 50 characters) summarizing the main work done
2. A brief summary (2-3 sentences) explaining what was accomplished
3. Infer a category (e.g., "Work > Development", "Personal > Learning", etc.)

IMPORTANT: Respond ONLY with a JSON object in this exact format:
```json
{
  "title": "Concise title",
  "summary": "Brief summary",
  "category": "Category > Subcategory"
}
```
"""
}
