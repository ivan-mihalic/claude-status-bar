// Tests/ClaudeStatusBarAppTests/ClickOutsideFocusTests.swift
import Testing
import AppKit
@testable import ClaudeStatusBarApp

@Test @MainActor func clickOnEditableTextField_keepsEditing() {
    let field = NSTextField(string: "Ivan")
    field.isEditable = true
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: field) == false)
}

@Test @MainActor func clickInsideTheFieldEditor_keepsEditing() {
    // While editing, the hit view is the field editor nested inside the text field.
    let field = NSTextField(string: "Ivan")
    field.isEditable = true
    let editor = NSTextView()
    editor.isEditable = true
    field.addSubview(editor)
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: editor) == false)
}

@Test @MainActor func clickOnALabel_endsEditing() {
    // A non-editable NSTextField is just a label — clicking it is clicking "outside".
    let label = NSTextField(labelWithString: "Menu label")
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: label) == true)
}

@Test @MainActor func clickOnAButtonOrEmptySpace_endsEditing() {
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: NSButton()) == true)
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: NSStepper()) == true)
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: NSView()) == true)
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: nil) == true)
}

@Test @MainActor func clickOnAControlNestedInsideATile_endsEditing() {
    // The tile that owns the text fields must not shield its other controls.
    let tile = NSView()
    let field = NSTextField(string: "Ivan")
    field.isEditable = true
    let button = NSButton()
    tile.addSubview(field)
    tile.addSubview(button)
    #expect(ClickOutsideFocus.shouldDismissEditing(clickedView: button) == true)
}
