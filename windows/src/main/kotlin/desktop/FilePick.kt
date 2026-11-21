package com.unoki99.fangfang.desktop

import java.awt.FileDialog
import java.awt.Frame
import java.io.File
import javax.swing.JFileChooser
import javax.swing.UIManager

/** the computer's own Save / Open dialogs (Windows', a Mac's) */
object FilePick {
    var window: Frame? = null
    private var lastDir: String? = System.getProperty("user.home") + File.separator + "Documents"

    fun save(name: String): File? {
        val d = FileDialog(window, "儲存", FileDialog.SAVE)
        d.directory = lastDir; d.file = name
        d.isVisible = true
        val f = d.file ?: return null
        lastDir = d.directory
        return File(d.directory, f)
    }

    fun open(): File? {
        val d = FileDialog(window, "開啟", FileDialog.LOAD)
        d.directory = lastDir
        d.isVisible = true
        val f = d.file ?: return null
        lastDir = d.directory
        return File(d.directory, f)
    }

    fun folder(): File? {
        if (Os.mac) {
            // (a Mac: its own folder dialog)
            System.setProperty("apple.awt.fileDialogForDirectories", "true")
            try {
                val d = FileDialog(window, "選擇資料夾", FileDialog.LOAD)
                d.directory = lastDir
                d.isVisible = true
                val f = d.file ?: return null
                lastDir = d.directory
                return File(d.directory, f)
            } finally { System.setProperty("apple.awt.fileDialogForDirectories", "false") }
        }
        try { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) } catch (_: Exception) {}
        val c = JFileChooser(lastDir)
        c.fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
        c.dialogTitle = "選擇資料夾"
        return if (c.showOpenDialog(window) == JFileChooser.APPROVE_OPTION) c.selectedFile else null
    }
}
