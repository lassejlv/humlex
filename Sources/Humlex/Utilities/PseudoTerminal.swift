import Foundation

/// A pseudo-terminal (PTY) wrapper for running an interactive shell
final class PseudoTerminal: ObservableObject {
    @Published var outputText: String = ""
    @Published var isRunning: Bool = false

    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var shellProcess: Process?
    private var readSource: DispatchSourceRead?
    private let outputQueue = DispatchQueue(label: "com.humlex.pty.output")
    private let shellPath: String
    private var currentDirectory: String

    init(workingDirectory: String? = nil) {
        self.shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.currentDirectory = workingDirectory ?? NSHomeDirectory()
    }

    deinit {
        stop()
    }

    /// Start the PTY and shell process
    func start() {
        guard !isRunning else { return }

        // Create pseudo-terminal
        var master: Int32 = 0
        var slave: Int32 = 0

        // Open PTY master/slave pair
        if openpty(&master, &slave, nil, nil, nil) == -1 {
            appendOutput("Error: Failed to create pseudo-terminal\n")
            return
        }

        masterFD = master
        slaveFD = slave

        // Set non-blocking on master
        let flags = fcntl(masterFD, F_GETFL)
        _ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

        // Set up terminal size
        var winSize = winsize()
        winSize.ws_col = 120
        winSize.ws_row = 30
        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)

        // Create and configure process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l"] // Login shell
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["HOME"] = NSHomeDirectory()
        env["LANG"] = "en_US.UTF-8"
        process.environment = env

        // Use the slave PTY for I/O
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        // Set up read source on master
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: outputQueue)
        source.setEventHandler { [weak self] in
            self?.readFromMaster()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.masterFD, fd != -1 {
                close(fd)
            }
            if let fd = self?.slaveFD, fd != -1 {
                close(fd)
            }
        }
        readSource = source
        source.resume()

        // Start the process
        do {
            try process.run()
            shellProcess = process
            isRunning = true
        } catch {
            appendOutput("Error starting shell: \(error.localizedDescription)\n")
            cleanup()
        }
    }

    /// Stop the PTY and shell process
    func stop() {
        readSource?.cancel()
        readSource = nil

        shellProcess?.terminate()
        shellProcess = nil

        if masterFD != -1 {
            close(masterFD)
            masterFD = -1
        }
        if slaveFD != -1 {
            close(slaveFD)
            slaveFD = -1
        }

        isRunning = false
    }

    /// Send input to the shell
    func send(_ text: String) {
        guard isRunning, masterFD != -1 else { return }

        if let data = text.data(using: .utf8) {
            data.withUnsafeBytes { bytes in
                _ = write(masterFD, bytes.baseAddress, data.count)
            }
        }
    }

    /// Send a line of input (with newline)
    func sendLine(_ text: String) {
        send(text + "\n")
    }

    /// Send Ctrl+C
    func sendInterrupt() {
        send("\u{03}") // Ctrl+C
    }

    /// Send Ctrl+D (EOF)
    func sendEOF() {
        send("\u{04}") // Ctrl+D
    }

    /// Send Ctrl+Z (suspend)
    func sendSuspend() {
        send("\u{1A}") // Ctrl+Z
    }

    /// Clear the output buffer
    func clearOutput() {
        DispatchQueue.main.async {
            self.outputText = ""
        }
    }

    /// Update terminal size
    func resize(columns: Int, rows: Int) {
        guard masterFD != -1 else { return }

        var winSize = winsize()
        winSize.ws_col = UInt16(columns)
        winSize.ws_row = UInt16(rows)
        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
    }

    // MARK: - Private

    private func readFromMaster() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(masterFD, &buffer, buffer.count)

        if bytesRead > 0 {
            if let text = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                appendOutput(text)
            }
        } else if bytesRead == 0 {
            // EOF - shell exited
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
        // bytesRead < 0 with EAGAIN is normal for non-blocking
    }

    private func appendOutput(_ text: String) {
        DispatchQueue.main.async {
            self.outputText += text
            // Limit buffer size to prevent memory issues
            if self.outputText.count > 100_000 {
                self.outputText = String(self.outputText.suffix(80_000))
            }
        }
    }

    private func cleanup() {
        if masterFD != -1 {
            close(masterFD)
            masterFD = -1
        }
        if slaveFD != -1 {
            close(slaveFD)
            slaveFD = -1
        }
        isRunning = false
    }
}
