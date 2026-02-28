// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKitCommands

@Suite("ColorOutput")
struct ColorOutputTests {

    @Test("Colors enabled when isEnabled is true")
    func colorsEnabled() {
        let color = ColorOutput(isEnabled: true)
        #expect(color.isEnabled)
    }

    @Test("noColor true disables colors")
    func noColorTrueDisablesColors() {
        let color = ColorOutput(noColor: true)
        #expect(!color.isEnabled)
    }

    @Test("success wraps in green ANSI code")
    func successWrapsInGreen() {
        let color = ColorOutput(isEnabled: true)
        let result = color.success("ok")
        #expect(result.contains("\u{1B}[32m"))
        #expect(result.contains("ok"))
        #expect(result.contains("\u{1B}[0m"))
    }

    @Test("error wraps in red ANSI code")
    func errorWrapsInRed() {
        let color = ColorOutput(isEnabled: true)
        let result = color.error("fail")
        #expect(result.contains("\u{1B}[31m"))
        #expect(result.contains("fail"))
    }

    @Test("warning wraps in yellow ANSI code")
    func warningWrapsInYellow() {
        let color = ColorOutput(isEnabled: true)
        let result = color.warning("warn")
        #expect(result.contains("\u{1B}[33m"))
        #expect(result.contains("warn"))
    }

    @Test("info wraps in cyan ANSI code")
    func infoWrapsInCyan() {
        let color = ColorOutput(isEnabled: true)
        let result = color.info("note")
        #expect(result.contains("\u{1B}[36m"))
        #expect(result.contains("note"))
    }

    @Test("bold wraps in bold ANSI code")
    func boldWrapsInBold() {
        let color = ColorOutput(isEnabled: true)
        let result = color.bold("title")
        #expect(result.contains("\u{1B}[1m"))
        #expect(result.contains("title"))
    }

    @Test("dim wraps in dim ANSI code")
    func dimWrapsInDim() {
        let color = ColorOutput(isEnabled: true)
        let result = color.dim("muted")
        #expect(result.contains("\u{1B}[2m"))
        #expect(result.contains("muted"))
    }

    @Test("colored with custom color")
    func coloredWithCustomColor() {
        let color = ColorOutput(isEnabled: true)
        let result = color.colored("text", .magenta)
        #expect(result.contains("\u{1B}[35m"))
        #expect(result.contains("text"))
    }

    @Test("When disabled, success returns plain text")
    func disabledSuccessReturnsPlainText() {
        let color = ColorOutput(isEnabled: false)
        let result = color.success("ok")
        #expect(result == "ok")
    }

    @Test("When disabled, error returns plain text")
    func disabledErrorReturnsPlainText() {
        let color = ColorOutput(isEnabled: false)
        let result = color.error("fail")
        #expect(result == "fail")
    }

    @Test("When disabled, all methods return unmodified text")
    func disabledAllMethodsReturnUnmodified() {
        let color = ColorOutput(isEnabled: false)
        #expect(color.warning("w") == "w")
        #expect(color.info("i") == "i")
        #expect(color.bold("b") == "b")
        #expect(color.dim("d") == "d")
        #expect(color.colored("c", .blue) == "c")
    }

    @Test("Empty string handling")
    func emptyStringHandling() {
        let color = ColorOutput(isEnabled: true)
        let result = color.success("")
        #expect(result.contains("\u{1B}[32m"))
        #expect(result.contains("\u{1B}[0m"))
    }

    @Test("ANSI codes are correct escape sequences")
    func ansiCodesCorrect() {
        #expect(ANSIColor.red.code == "\u{1B}[31m")
        #expect(ANSIColor.green.code == "\u{1B}[32m")
        #expect(ANSIColor.yellow.code == "\u{1B}[33m")
        #expect(ANSIColor.blue.code == "\u{1B}[34m")
        #expect(ANSIColor.cyan.code == "\u{1B}[36m")
        #expect(ANSIColor.magenta.code == "\u{1B}[35m")
        #expect(ANSIColor.bold.code == "\u{1B}[1m")
        #expect(ANSIColor.dim.code == "\u{1B}[2m")
        #expect(ANSIColor.reset.code == "\u{1B}[0m")
    }

    @Test("ExitCodes constants have correct values")
    func exitCodesCorrectValues() {
        #expect(ExitCodes.success == 0)
        #expect(ExitCodes.generalError == 1)
        #expect(ExitCodes.connectionError == 2)
        #expect(ExitCodes.authenticationError == 3)
        #expect(ExitCodes.fileError == 4)
        #expect(ExitCodes.argumentError == 5)
        #expect(ExitCodes.serverError == 6)
        #expect(ExitCodes.timeout == 7)
    }

    @Test("NO_COLOR convention disables colors")
    func noColorConvention() {
        // When NO_COLOR is set, ColorOutput() should disable colors
        // This is tested indirectly: noColor: true mimics the same behavior
        let color = ColorOutput(noColor: true)
        #expect(!color.isEnabled)
        #expect(color.success("text") == "text")
    }
}
