import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("每日表达报告")
                    .font(.largeTitle.bold())

                ReportRow(title: "今日字数", value: "\(viewModel.report.totalWords)")
                ReportRow(title: "转写次数", value: "\(viewModel.report.transcribeCount)")
                ReportRow(title: "训练次数", value: "\(viewModel.report.trainingCount)")
                ReportRow(title: "优化次数", value: "\(viewModel.report.polishCount)")
                ReportRow(title: "语音输入次数", value: "\(viewModel.report.speechInputCount)")
                ReportRow(title: "口头禅次数", value: "\(viewModel.report.catchphraseCount)")

                VStack(alignment: .leading, spacing: 8) {
                    Text("今日最佳一句")
                        .font(.headline)
                    Text(viewModel.report.bestSentence)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("报告")
        .task {
            await viewModel.loadReport()
        }
    }
}

private struct ReportRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .bold()
                .foregroundStyle(.orange)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
