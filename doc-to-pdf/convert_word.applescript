on run argv
    set sourcePath to item 1 of argv
    set outputPath to item 2 of argv
    set sourceAlias to (POSIX file sourcePath) as alias
    set outputHFS to (POSIX file outputPath) as text

    tell application id "com.microsoft.Word"
        set didOpen to false
        try
            open sourceAlias
            set didOpen to true
            tell active document
                save as it file name outputHFS file format format PDF
                close saving no
            end tell
        on error errorMessage number errorNumber
            if didOpen then
                try
                    close active document saving no
                end try
            end if
            error errorMessage number errorNumber
        end try
    end tell
end run
