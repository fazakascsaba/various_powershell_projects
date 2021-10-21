# --- functions

Function create-logFile{
    if (!(Test-Path "$BFLocation\$logfile")){
            New-Item -path $BFLocation -name $logfile -type "file" | Out-Null
        }
}
Function log{
    param (
        [String]$text
    )
    "$(get-date) $text" | Tee-Object -FilePath $fullLogfile -Append
}



# --- initialization

$workDir='C:\ep40'
$BFLocation="C:\EP40\BatchFacility"
$logfile="OutgoingStarter.log"
$fullLogfile="$BFLocation\$logfile"

sl $workDir
create-logFile
log "Process started."

# --- collect bin work folders

$foldersOfInterest=@()
gci -directory -name | %{
    if($_ -match '^C\d{6,6}$'){
        $foldersOfInterest+=$_
    }
}


# --- check for outgoing file and execute scheduled task if available

$foldersOfInterest | %{
    $bin=$_.Substring(1,6)
    $files=@()
    gci "$workDir\$_\OUTGOING" -file -name | %{
        if($_ -match '\.CTF$'){
            log "$bin has this file staged: $_"
            $files+=$_
        }
    }
    if($files){
        log "Starting outgoing run for $bin"
        C:\EP40\BatchFacility\ep.ps1 -bin $bin -runtype out
    }
}
log "Process finished."
