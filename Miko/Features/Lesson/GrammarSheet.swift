import SwiftUI

/// Reusable sheet presenting a `GrammarTopic` tied to the current lesson.
/// Content comes entirely from seed data — no grammar text is hardcoded here.
struct GrammarSheet: View {
    let topic: GrammarTopic
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        NSLocalizedString(topic.titleKey, comment: "Grammar topic title")
    }

    private var explanation: String {
        NSLocalizedString(topic.explanationKey, comment: "Grammar topic explanation")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TDSpacing.l) {
            HStack {
                Text(title)
                    .font(TDTypography.title)
                    .foregroundStyle(TDColor.textPrimary)
                Spacer()
                Button {
                    dismiss()
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(TDColor.textSecondary)
                }
                .accessibilityLabel("grammar.sheet.close")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: TDSpacing.l) {
                    MascotView(mood: .teacher, size: 170)
                        .frame(maxWidth: .infinity, alignment: .center)

                    TDCard {
                        Text(explanation)
                            .font(TDTypography.body)
                            .foregroundStyle(TDColor.textPrimary)
                    }

                    if !topic.examples.isEmpty {
                        Text("grammar.sheet.examples")
                            .font(TDTypography.sectionTitle)
                            .foregroundStyle(TDColor.textPrimary)

                        VStack(spacing: TDSpacing.s) {
                            ForEach(topic.examples, id: \.self) { example in
                                TDCard {
                                    Text(example)
                                        .font(TDTypography.body)
                                        .foregroundStyle(TDColor.primary)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, TDSpacing.l)
            }
        }
        .padding(TDSpacing.m)
        .background(TDColor.background)
    }
}
