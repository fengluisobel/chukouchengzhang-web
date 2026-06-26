import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        List {
            Section("我的灵感") {
                if viewModel.ideas.isEmpty {
                    Text("还没有归档内容。")
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.ideas) { idea in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(idea.title)
                                .font(.headline)
                            Spacer()
                            Text(idea.category.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Text(idea.normalizedText)
                            .lineLimit(3)
                        Text("下一步：\(idea.nextAction)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(idea.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("灵感库")
        .task {
            await viewModel.loadIdeas()
        }
    }
}
