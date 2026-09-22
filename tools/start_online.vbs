Option Explicit
Dim shell, fs, folder, command, arg, matcher
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
folder = fs.GetParentFolderName(WScript.ScriptFullName)
If fs.FileExists(fs.BuildPath(folder, "RoweModOnline.exe")) Then
    command = """" & fs.BuildPath(folder, "RoweModOnline.exe") & """"
Else
    command = "pythonw.exe """ & fs.BuildPath(folder, "mp_online.py") & """"
End If
Set matcher = New RegExp
matcher.Pattern = "^(\+connect_lobby|--background|[0-9]{1,20})$"
For Each arg In WScript.Arguments
    If Not matcher.Test(arg) Then WScript.Quit 1
    command = command & " " & arg
Next
shell.Run command, 0, False
