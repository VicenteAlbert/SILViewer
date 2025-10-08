import Combine
import SwiftUI

// HACK to work-around the smart quote issue
extension NSTextView {
    open override var frame: CGRect {
        didSet {
            self.isAutomaticQuoteSubstitutionEnabled = false
        }
    }
}

struct ContentView: View {

    @StateObject private var viewModel = ViewModel()
    private let sizes = Array(12...36).map(CGFloat.init)
    @State private var fontSize: CGFloat = 22

    var body: some View {
        TabView(selection: $viewModel.selectedTab) {
            TextEditor(text: $viewModel.source)
                .font(.system(size: fontSize))
                .tabItem { Text("Source code") }
                .tag(Tab.code)
            buildView(for: $viewModel.parseOutput)
                .tabItem { Text("Parse") }
                .tag(Tab.parse)
            buildView(for: $viewModel.astOutput)
                .tabItem { Text("AST") }
                .tag(Tab.ast)
            buildView(for: $viewModel.prettyPrintAST)
                .tabItem { Text("Pre-SIL Swift from AST") }
                .tag(Tab.prettyPrintAST)
            buildView(for: $viewModel.silOutput)
                .tabItem { Text("Raw SIL") }
                .tag(Tab.sil)
            buildView(for: $viewModel.canonicalSilOutput)
                .tabItem { Text("Canonical SIL") }
                .tag(Tab.canonicalSil)
            buildView(for: $viewModel.irOutput)
                .tabItem { Text("IR") }
                .tag(Tab.ir)
            buildView(for: $viewModel.assmeblyOutput)
                .tabItem { Text("Assembly") }
                .tag(Tab.assembly)
        }
        .font(.system(size: 18))
    }

    var optionsView: some View {
        HStack {
            Toggle("Demangle", isOn: $viewModel.demangle)
            Toggle("Optimize", isOn: $viewModel.optimize)
            Toggle("Module optimize", isOn: $viewModel.moduleOptimize)
            Toggle("Parse as library", isOn: $viewModel.parseAsLibrary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("Font size")
                Slider(value: $fontSize, in: (12...36), step: 1)
            }
        }
    }

    func buildView(for binding: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            optionsView
                .padding(8)
            TextEditor(text: binding)
                .font(.system(size: fontSize))
            Button {
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(viewModel.commandRun, forType: .string)
            } label: {
                Label(viewModel.commandRun, systemImage: "document.on.document")
                    .padding(8)
            }
            .padding(8)
        }
    }
}

extension ContentView {
    enum Tab: String {
        case code, ast, prettyPrintAST, parse, sil, canonicalSil, ir, assembly
    }
    final class ViewModel: ObservableObject {
        private var cancellables = [AnyCancellable]()
        @Published var selectedTab = Tab.code
        @Published var demangle = true
        @Published var optimize = false
        @Published var moduleOptimize = false
        @Published var parseAsLibrary = false
        @Published var source = "// Paste or write your Swift code here"
        @Published var commandRun = ""

        @Published var silOutput: String = ""
        @Published var canonicalSilOutput: String = ""
        @Published var irOutput: String = ""
        @Published var parseOutput: String = ""
        @Published var prettyPrintAST: String = ""
        @Published var astOutput: String = ""
        @Published var assmeblyOutput: String = ""

        init() {
            $demangle
                .combineLatest($optimize, $moduleOptimize, $parseAsLibrary)
                .sink { [weak self] demangle, optimize, moduleOptimize, parseAsLibrary in
                    guard let self else { return }
                    let params = (demangle, optimize, moduleOptimize, parseAsLibrary)
                    run(params: params, tab: selectedTab)
                }
                .store(in: &cancellables)
            $selectedTab
                .sink { [weak self] tab in
                    guard let self else { return }
                    let params = (demangle, optimize, moduleOptimize, parseAsLibrary)
                    run(params: params, tab: tab)
                }
                .store(in: &cancellables)
        }

        func withParseAsLibrary(_ parseAsLibrary: Bool, _ program: String) -> String {
            parseAsLibrary ? program + " -parse-as-library -module-name SILInspector" : program
        }

        func withOptimize(_ optimize: Bool, _ program: String) -> String {
            optimize ? program + " -O" : program
        }

        func withModuleOptimize(_ moduleOptimize: Bool, _ program: String) -> String {
            moduleOptimize ? program + " -whole-module-optimization" : program
        }

        func withDemangle(_ demangle: Bool, _ program: String) -> String {
            demangle ? program + " | xcrun swift-demangle" : program
        }

        func run(params: (Bool, Bool, Bool, Bool), tab: Tab) {
            let programTemplate = withDemangle(
                params.0,
                withOptimize(
                    params.1,
                    withModuleOptimize(
                        params.2,
                        withParseAsLibrary(
                            params.3,
                            "%@"
                        )
                    )
                )
            )
            switch tab {
            case .sil:
                let command = String(format: programTemplate, "swiftc - -emit-silgen")
                commandRun = command
                silOutput = runProgram(command)
            case .ir:
                let command = String(format: programTemplate, "swiftc - -emit-ir")
                commandRun = command
                irOutput = runProgram(command)
            case .ast:
                let command = "swiftc - -dump-ast"
                commandRun = command
                astOutput = runProgram(command)
            case .parse:
                let command = "swiftc - -dump-parse"
                commandRun = command
                parseOutput = runProgram(command)
            case .canonicalSil:
                let command = String(format: programTemplate, "swiftc - -emit-sil")
                commandRun = command
                canonicalSilOutput = runProgram(command)
            case .assembly:
                let command = String(format: programTemplate, "swiftc - -emit-assembly")
                commandRun = command
                assmeblyOutput = runProgram(command)
            case .prettyPrintAST:
                let command = "swiftc - -print-ast"
                commandRun = command
                prettyPrintAST = runProgram(command)
            case .code:
                break
            }
        }

        func runProgram(_ program: String) -> String {
            let inputPipe = Pipe()
            let inputFile = inputPipe.fileHandleForWriting
            inputFile.write(Data(source.utf8))
            inputFile.closeFile()
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", program]
            let errorPipe = Pipe()
            let outputPipe = Pipe()
            task.standardInput = inputPipe
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            task.launch()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outputData, as: UTF8.self)
            let error = String(decoding: errorData, as: UTF8.self)
            return error == "" || error == "\n" ? output : error
        }
    }
}

#Preview {
    ContentView()
}
