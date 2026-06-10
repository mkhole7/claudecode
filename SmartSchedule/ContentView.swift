import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var voice = VoiceRecognizer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InputCard(viewModel: viewModel, voice: voice)

                    if viewModel.parsedItem != nil {
                        ParsedItemCard(viewModel: viewModel)
                    } else {
                        ExamplesCard(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("스마트 일정관리")
            .navigationBarTitleDisplayMode(.large)
            .alert(
                viewModel.alertIsSuccess ? "완료" : "오류",
                isPresented: $viewModel.showAlert
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage)
            }
            .alert("음성 인식 오류", isPresented: .constant(voice.errorMessage != nil)) {
                Button("확인", role: .cancel) { voice.errorMessage = nil }
            } message: {
                Text(voice.errorMessage ?? "")
            }
        }
        .onChange(of: voice.transcribedText) { text in
            if !text.isEmpty { viewModel.inputText = text }
        }
        .onChange(of: voice.isRecording) { recording in
            if !recording && !voice.transcribedText.isEmpty {
                viewModel.parseInput()
            }
        }
    }
}

// MARK: - Input Card

struct InputCard: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var voice: VoiceRecognizer
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("일정 입력", systemImage: "text.cursor")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))

                if viewModel.inputText.isEmpty && !voice.isRecording {
                    Text("텍스트 입력 또는 🎤 음성 입력")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                if voice.isRecording {
                    VStack {
                        HStack(spacing: 8) {
                            RecordingIndicator()
                            Text("듣는 중...")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                        .padding(.top, 12)
                        .padding(.leading, 12)
                        if !voice.transcribedText.isEmpty {
                            Text(voice.transcribedText)
                                .foregroundColor(.primary)
                                .font(.body)
                                .padding(.horizontal, 12)
                                .padding(.top, 4)
                        }
                        Spacer()
                    }
                } else {
                    TextEditor(text: $viewModel.inputText)
                        .frame(minHeight: 90)
                        .padding(8)
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                }
            }
            .frame(minHeight: 90)

            HStack(spacing: 10) {
                // Voice button
                Button {
                    isFocused = false
                    if voice.isRecording {
                        Task { await voice.stopRecording() }
                    } else {
                        viewModel.inputText = ""
                        Task { await voice.startRecording() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                        Text(voice.isRecording ? "중지" : "음성")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(voice.isRecording ? Color.red : Color(.secondarySystemBackground))
                    .foregroundColor(voice.isRecording ? .white : .primary)
                    .cornerRadius(12)
                }

                // Parse button
                Button {
                    isFocused = false
                    viewModel.parseInput()
                } label: {
                    Label("분석하기", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || voice.isRecording)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .scaleEffect(animating ? 1.3 : 0.8)
            .opacity(animating ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.6).repeatForever(), value: animating)
            .onAppear { animating = true }
    }
}

// MARK: - Parsed Item Card

struct ParsedItemCard: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var isEditingTitle = false
    @State private var editTitle = ""

    private var item: ParsedItem? { viewModel.parsedItem }

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 16) {
                headerRow(item: item)
                Divider()
                typePicker(item: item)
                titleRow(item: item)
                dateRow(item: item)
                if item.type == .reminder { categoryRow(item: item) }
                Divider()
                actionButtons(item: item)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

    @ViewBuilder
    private func headerRow(item: ParsedItem) -> some View {
        HStack {
            Label("분석 결과", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundColor(.green)
            Spacer()
            let color: Color = item.confidence >= 0.8 ? .green : item.confidence >= 0.6 ? .orange : .red
            Text("\(Int(item.confidence * 100))% 확신")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func typePicker(item: ParsedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("종류").font(.caption).foregroundColor(.secondary)
            Picker("종류", selection: Binding(
                get: { item.type },
                set: { viewModel.editType($0) }
            )) {
                ForEach(ScheduleType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func titleRow(item: ParsedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("제목").font(.caption).foregroundColor(.secondary)
            if isEditingTitle {
                HStack {
                    TextField("제목", text: $editTitle).textFieldStyle(.roundedBorder)
                    Button("완료") { viewModel.editTitle(editTitle); isEditingTitle = false }
                        .foregroundColor(.accentColor)
                }
            } else {
                HStack {
                    Text(item.title).font(.body.weight(.medium))
                    Spacer()
                    Button { editTitle = item.title; isEditingTitle = true } label: {
                        Image(systemName: "pencil").foregroundColor(.accentColor)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dateRow(item: ParsedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("날짜/시간").font(.caption).foregroundColor(.secondary)
            HStack {
                Image(systemName: "clock").foregroundColor(.secondary)
                Text(item.formattedDate).font(.subheadline)
                Spacer()
                Button {
                    selectedDate = item.startDate ?? Date()
                    withAnimation { showDatePicker.toggle() }
                } label: {
                    Image(systemName: showDatePicker ? "chevron.up" : "pencil")
                        .foregroundColor(.accentColor)
                }
            }
            if showDatePicker {
                DatePicker("날짜/시간", selection: $selectedDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact).labelsHidden()
                    .onChange(of: selectedDate) { viewModel.editDate($0) }
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func categoryRow(item: ParsedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("목록").font(.caption).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReminderCategory.allCases, id: \.self) { cat in
                        Button { viewModel.editCategory(cat) } label: {
                            Label(cat.rawValue, systemImage: cat.icon)
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(item.reminderCategory == cat ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(item.reminderCategory == cat ? .white : .primary)
                                .cornerRadius(20)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(item: ParsedItem) -> some View {
        HStack(spacing: 12) {
            Button("취소") { viewModel.cancel() }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(.primary).cornerRadius(12)

            Button {
                Task { await viewModel.confirmAction() }
            } label: {
                if viewModel.isProcessing {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                } else {
                    Text(item.type == .calendarEvent ? "캘린더에 추가" : "미리알림에 추가")
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.accentColor).foregroundColor(.white).cornerRadius(12)
            .disabled(viewModel.isProcessing)
        }
    }
}

// MARK: - Examples Card

struct ExamplesCard: View {
    @ObservedObject var viewModel: MainViewModel

    private struct Example { let icon: String; let text: String; let color: Color }
    private let examples = [
        Example(icon: "calendar", text: "내일 오후 3시에 팀 미팅", color: .blue),
        Example(icon: "calendar", text: "다음주 월요일 오전 10시 치과 예약", color: .blue),
        Example(icon: "briefcase.fill", text: "이번 주 금요일까지 보고서 제출", color: .orange),
        Example(icon: "cart.fill", text: "마트에서 우유, 계란, 두부 사기", color: .green),
        Example(icon: "figure.run", text: "오늘 저녁 6시 헬스장 운동", color: .red),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("입력 예시 (탭하면 입력)", systemImage: "lightbulb.fill")
                .font(.headline).foregroundColor(.orange)
            ForEach(examples, id: \.text) { ex in
                Button { viewModel.inputText = ex.text } label: {
                    HStack(spacing: 12) {
                        Image(systemName: ex.icon).foregroundColor(ex.color).frame(width: 24)
                        Text(ex.text).font(.subheadline).foregroundColor(.primary).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview { ContentView() }
