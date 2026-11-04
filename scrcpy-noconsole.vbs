' Launch scrcpy.exe (now located in bin\) without a console window.
' CurrentDirectory is set to this folder so that the portable icon lookup works.

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("Wscript.Shell")

strRoot = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = strRoot

strCommand = "cmd /c """ & strRoot & "\bin\scrcpy.exe"""

For Each Arg In WScript.Arguments
    strCommand = strCommand & " """ & replace(Arg, """", """""""""") & """"
Next

sh.Run strCommand, 0, false
