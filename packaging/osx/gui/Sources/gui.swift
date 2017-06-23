import Cocoa

class AgentGUI: NSObject {
    var systemTrayItem: NSStatusItem!
    var ddMenu: NSMenu!
    var versionItem: NSMenuItem!
    var startItem: NSMenuItem!
    var stopItem: NSMenuItem!
    var restartItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var exitItem: NSMenuItem!
    var countUpdate: Int
    var agentStatus: Bool!
    var loginStatus: Bool!
    var updatingAgent: Bool!
    var loginStatusEnableTitle = "Enable at login"
    var loginStatusDisableTitle = "Disable at login"


    override init() {
        // initialising at for update
        countUpdate = 10

        super.init()

        NSApplication.shared()

        ddMenu = NSMenu(title: "Menu")
        ddMenu.autoenablesItems = true

        // Create menu items
        versionItem = NSMenuItem(title: "Datadog Agent", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        startItem = NSMenuItem(title: "Start", action: #selector(startAgent), keyEquivalent: "")
        startItem.target = self
        stopItem = NSMenuItem(title: "Stop", action: #selector(stopAgent), keyEquivalent: "")
        stopItem.target = self
        restartItem = NSMenuItem(title: "Restart", action: #selector(restartAgent), keyEquivalent: "")
        restartItem.target = self
        loginItem = NSMenuItem(title: loginStatusEnableTitle, action: #selector(loginAction), keyEquivalent: "")
        loginItem.target = self
        exitItem = NSMenuItem(title: "Exit", action: #selector(exitGUI), keyEquivalent: "")
        exitItem.target = self

        ddMenu.addItem(versionItem)
        ddMenu.addItem(NSMenuItem.separator())
        ddMenu.addItem(startItem)
        ddMenu.addItem(stopItem)
        ddMenu.addItem(restartItem)
        ddMenu.addItem(loginItem)
        ddMenu.addItem(exitItem)

        // Create tray icon
        systemTrayItem = NSStatusBar.system().statusItem(withLength: NSVariableStatusItemLength)

        // Set image
        let ddImage =  NSImage(byReferencingFile: "../agent.png")
        ddImage!.size = NSMakeSize(15, 15)
        systemTrayItem!.button!.image = ddImage

        systemTrayItem!.menu = ddMenu
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Count to check only once agent status
        if (self.countUpdate >= 5){
            if (self.updatingAgent){
                disableActionItems()
            }
            else {
                self.countUpdate = 0
                DispatchQueue.global().async {
                    self.agentStatus = AgentManager.status()
                    DispatchQueue.main.async(execute: {
                        self.updateMenuItems(agentStatus: self.agentStatus)
                        })
                    }
                }
            }

        self.countUpdate += 1

        return menuItem.isEnabled
    }

    func run() {
        // Initialising
        agentStatus = AgentManager.status()
        loginStatus = AgentManager.getLoginStatus()
        updateLoginItem()
        updatingAgent = false
        NSApp.run()
    }

    func disableActionItems(){
        startItem.isEnabled = false
        stopItem.isEnabled = false
        restartItem.isEnabled = false
    }

    func updateMenuItems(agentStatus: Bool) {
        startItem.isEnabled = !agentStatus
        stopItem.isEnabled = agentStatus
        restartItem.isEnabled = agentStatus
    }

    func updateLoginItem() {
        loginItem.title = loginStatus! ? loginStatusDisableTitle : loginStatusEnableTitle
    }

    func loginAction(_ sender: Any?) {
        self.loginStatus = AgentManager.switchLoginStatus()
        updateLoginItem()
    }

    func startAgent(_ sender: Any?) {
        self.commandAgent(command: "start")
    }

    func stopAgent(_ sender: Any?) {
        self.commandAgent(command: "stop")
    }

    func restartAgent(_ sender: Any?) {
        self.commandAgent(command: "restart")
    }

    func commandAgent(command: String) {
        self.updatingAgent = true
        DispatchQueue.global().async {
            self.disableActionItems()

            // Sending agent command
            AgentManager.exec(command: command)
            self.agentStatus = AgentManager.status()

            DispatchQueue.main.async(execute: {
                // Updating the menu items after completion
                self.updatingAgent = false
                self.updateMenuItems(agentStatus: self.agentStatus)
            })
        }
    }

    func exitGUI(_ sender: Any?) {
        NSApp.terminate(sender)
    }
}

class AgentManager {
    static let systemEventsCommandFormat = "tell application \"System Events\" to %@"

    static func status() -> Bool {
        return call(command: "status").exitCode == 0
    }

    static func exec(command: String) {
        let processInfo = call(command: command)
        if processInfo.exitCode != 0 {
            NSLog(processInfo.stdOut)
            NSLog(processInfo.stdErr)
        }
    }

    static func call(command: String) -> (exitCode: Int32, stdOut: String, stdErr: String) {
        let stdOutPipe = Pipe()
        let stdErrPipe = Pipe()
        let process = Process()
        process.launchPath = "/usr/local/bin/datadog-agent"
        process.arguments = [command]
        process.standardOutput = stdOutPipe
        process.standardError = stdErrPipe
        process.launch()
        process.waitUntilExit()
        let stdOut = String(data: stdOutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: String.Encoding.utf8)
        let stdErr = String(data: stdErrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: String.Encoding.utf8)

        return (process.terminationStatus, stdOut!, stdErr!)
    }

    static func getLoginStatus() -> Bool {
        let processInfo = callSystemEvents(command: "get the path of every login item whose name is \"Datadog Agent\"")
        return processInfo.stdOut.contains("Datadog")
    }

    static func switchLoginStatus() -> Bool {
        let currentLoginStatus = getLoginStatus()
        var command: String
        if currentLoginStatus { // enabled -> disable
            command = "delete every login item whose name is \"Datadog Agent\""
        } else { // disabled -> enable
            command = "make login item at end with properties {path:\"/Applications/Datadog Agent.app\", name:\"Datadog Agent\", hidden:false}"
        }
        let processInfo = callSystemEvents(command: command)
        if processInfo.exitCode != 0 {
            NSLog(processInfo.stdOut)
            NSLog(processInfo.stdErr)
            return currentLoginStatus
        }

        return !currentLoginStatus
    }

    static func callSystemEvents(command: String) -> (exitCode: Int32, stdOut: String, stdErr: String) {
        let stdOutPipe = Pipe()
        let stdErrPipe = Pipe()
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", String(format: systemEventsCommandFormat, command)]
        process.standardOutput = stdOutPipe
        process.standardError = stdErrPipe
        process.launch()
        process.waitUntilExit()
        let stdOut = String(data: stdOutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: String.Encoding.utf8)
        let stdErr = String(data: stdErrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: String.Encoding.utf8)

        return (process.terminationStatus, stdOut!, stdErr!)
    }
}
