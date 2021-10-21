# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# Please do not execute this app unless you know what it does
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


param (
    [Parameter(Mandatory)]$bin, 
    [Parameter(Mandatory)]$runType
)


Function validate-inputParameters{
    $folderName=get-childitem $BFLocation\*$bin*$runType -Attributes Directory -name
    if(-not $folderName){
        log -text ""
        log -text "FATAL [$bin $runType] Input parameters ($bin & $runType) do not point to an existing process. Process will exit."
        start-sleep 5
        exit
    }
    return $folderName
}
Function create-logFile{
    if (!(Test-Path "$BFLocation\$logfile")){
            New-Item -path $BFLocation -name $logfile -type "file" | Out-Null
        }
}
Function log{
    param (
        [String]$text
    )
    $logfile="C:\EP40\BatchFacility\EP.log"
    "$(get-date) $text" | Tee-Object -FilePath $logfile -Append
}
Function create-semaphore {
    $tic=get-date
    write-host "[$bin $runType] INFO Checking Semaphore file..."
    if(Test-Path $semaphoreFile){
        while(Test-Path $semaphoreFile){
            $timeout=[int]$($(get-date)-$tic).minutes
            write-host "[$bin $runType] WARN Semaphore file ($semaphoreFile) present we are waiting. Wait time: $timeout minutes."
            start-sleep 10
            if([int]$timeout -gt 60){
                log -text "FATAL [$bin $runType] A process is executing for more than $timeout minutes. Please check $semaphoreFile for details. Process will exit."
                exit
            }
        }
    }
       
    log -text "INFO [$bin $runType] Creating semaphore file: $semaphoreFile."
    "$bin $runType" > $semaphoreFile
}
Function check-EditPackage{
    log -text "INFO [$bin $runType] Checking Edit Package..."
    $suspend=$true
    while ($suspend){
        try{
            get-process EPWIN400 -ErrorAction Stop | Out-Null
            log -text "WARN [$bin $runType] Edit Package executing. Waiting..."
            start-sleep 10
            }catch{
                $suspend=$false
            }
        }
    log -text "INFO [$bin $runType] Edit Package is not executing. Moving on."
}
Function call-batchFacility{
    # MAIN PART
    log -text "INFO [$bin $runType] Main execution part starting."
    set-location "$BFLocation\$batchFolder"
    $bat="$($batchFolder).bat"
    log -text "INFO [$bin $runType] Calling  $BFLocation\$batchFolder\$bat"
    log -text "INFO [$bin $runType] BATCH PART @START@"
    & .\$bat 
    log -text "INFO [$bin $runType] BATCH PART @END@ "
}
Function check-resultAndCallPostProcess{
    set-location "$BFLocation\$batchFolder"
    $runlog = gci *.log | sort LastWriteTime | select -last 1
    if($runlog -and $runlog.CreationTime -gt $pgmStartTime){
        log -text "INFO [$bin $runType] Validate BatchFacility run result..."
        $runResult=99
        gc $runlog | %{
            if($_ -like "*EPBatch-procedure*ended*"){
                $pos=[int]$($_.indexof("RC="))
                $pos += 3
                $runResult=$_.substring($pos)
            }
        }

        # delivery part
        if([int]$runResult -le 4){
            log -text "INFO [$bin $runType] EditPackage RC=$runResult"
            if($runType -eq "inc"){extract-itf -runlog $runlog}
            call-postprocess
        }elseif($runResult -eq 99){
            log -text "ERROR [$bin $runType] Result code could not be extracted."
        }elseif($runResult -eq 20){
            log -text "WARN [$bin $runType] Result code RC=$runResult received. No incoming file on EAS for this CIB. You might want to retry later."
        }else{
            log -text "ERROR [$bin $runType] EditPackage RC=$runResult, please check latest BatchFacility log for this BIN/CIB. Escalate if chinese."
            if($runType -eq "inc"){extract-itf -runlog $runlog}
        }
    }
}
Function extract-itf{
    param (
        [String]$runlog
    )
    $itfFile=@()
    gc $runlog | %{if($_ -like "*Staging incoming file*"){
        $itfFile += $_.split("\")[4].split(".")[0]
        }
    }
    log -text "INFO [$bin $runType] EditPackage downloaded these itf files: $itfFile"
}
Function remove-semaphore{
    log -text "INFO [$bin $runType] Removing Semaphore file..."
    remove-item $semaphoreFile
    if(Test-Path $semaphoreFile){
        log -text "ERROR [$bin $runType] Semaphore file was not removed. Please delete manually and check EP run."
    }else{
        log -text "INFO [$bin $runType] Semaphore file removed." 
    }
}
Function call-postprocess{
    if("$bin$runType" -eq "439747inc"){
        pp_inc_generic
    }elseif("$bin$runType" -eq "439747ardef"){
        pp_ardef
    }elseif("$bin$runType" -in "439747outreport","439747out"){
        pp_out_generic
    }else{
        return
    }

}
Function pp_inc_generic{
    # save initial path
    $path=$(get-location).path
    
    #############################################
    # package reports and stage to jenkins folder
    #############################################
    sl "C:\EP40\C$bin\REPORTS\INCOMING"
    $reportsFolder=gci -path "C:\EP40\C$bin\REPORTS\INCOMING" -filter "d$(get-date -format 'yyMMdd')*" -directory | where-object{$_.LastWriteTime -gt $pgmStartTime}
    
    $test=$False

    if($test){
        $a='d210927_r1_t120523_prod_v2'       
        $b='EPIN_BPCPS_439747_20210927_001_PROD_2021-09-27-12-05-30_v2.TXT'
        rename-item $reportsFolder $a    
        $reportsFolder=$a               
    }

    if($reportsFolder){
        7z a -tzip "C:\EP40\C$bin\REPORTS\INCOMING\$reportsFolder.zip" $reportsFolder
        if($?){
            if($test){
                Copy-Item "C:\EP40\C$bin\REPORTS\INCOMING\$reportsFolder.zip" "C:\EP40\C$bin\REPORTS\INCOMING\temp_folder\$reportsFolder.zip"
            }else{
                Copy-Item "C:\EP40\C$bin\REPORTS\INCOMING\$reportsFolder.zip" "C:\EP40\C$bin\REPORTS\INCOMING\jenkins\$reportsFolder.zip"
            }
            
            Remove-Item -LiteralPath "C:\EP40\C$bin\REPORTS\INCOMING\$reportsFolder" -Force -Recurse
        }
    }

    #############################################
    # package inc run artifacts
    #############################################
    sl "C:\EP40\C$bin\INCOMING"
    if(-not(test-path jenkins)){new-item jenkins -ItemType directory}
    $files=gci * -file -include "EPIN*.TXT","EP.CUR.RATE.TXT","RETURN.ITEMS.TXT","REJECT.TRANS.TXT","TC33EX.TXT",
    "TC54EX.TXT","TRACETRAN.EPBLAZ.TXT","EPCHGMGT.LOG" -name 
    log -text "INFO [$bin $runType] Archiving files in $(get-location)."

    $date=get-date -format "yyyy-MM-dd-HH-mm-ss"
    if($files){
        log -text "INFO [$bin $runType] Creating archive $date.zip, files added: $files."
        $compress=@{
            Path=$files
            CompressionLevel="Fastest"
            DestinationPath="$date.zip"
        }
        Compress-archive @compress
        $compress_success=$?
    }
    
    #############################################
    # rename EPIN.TXT and stage to jenkins folder
    #############################################
    $date1=get-date -format "yyyyMMdd"
    log -text "INFO [$bin $runType] Moving & renaming EPIN.TXT."
    
    # this is temporary ---- NO RENAME AND MOVE IS NEEDED ---- 
    # Jenkins should go to the proper folder to pickup the files
    if(test-path "EPIN.TXT"){
        if("$bin$runType" -eq "<BIN>inc"){
            log -text "INFO [$bin $runType] EPIN.TXT moving to C:\EP40\C<BIN>\INCOMING\jenkins\EPIN_BPCPS_$($bin)_$($date1)_001_PROD_$date.TXT"
            if($test){
                copy-item "EPIN.TXT" "C:\EP40\C<BIN>\INCOMING\temp_folder\$b"
            }else{
                copy-item "EPIN.TXT" "C:\EP40\C<BIN>\INCOMING\jenkins\EPIN_BPCPS_$($bin)_$($date1)_001_PROD_$date.TXT"
            }
        }else{
            log -text "ERROR [$bin $runType] EPIN.txt does not exist."
        }
    }

    if($compress_success){$files | remove-item}

      
    # restore initial path
    set-location $path
}
Function pp_out_generic{
    # save initial path
    $path=$(get-location).path


    #############################################
    # package reports and stage to jenkins folder
    #############################################
    set-location "C:\EP40\C$bin\REPORTS\OUTGOING"
    $year=[String]$(get-date).year
    if(-not (test-path $year)){new-item $year -ItemType directory}
    $reportsFolder=gci -path "C:\EP40\C$bin\REPORTS\OUTGOING" -filter "d$(get-date -format 'yyMMdd')*" -directory | where-object{$_.LastWriteTime -gt $pgmStartTime}

    $test=$false

    if($test){
        $a='d210801_r1_t020220_prod_v2' 
        rename-item $reportsFolder $a   
        $reportsFolder=$a       
    }        

    if($reportsFolder){
        7z a -tzip "C:\EP40\C$bin\REPORTS\OUTGOING\$reportsFolder.zip" $reportsFolder
    
        if($?){
            if($test){
                Copy-Item "C:\EP40\C$bin\REPORTS\OUTGOING\$reportsFolder.zip" "C:\EP40\C$bin\REPORTS\OUTGOING\temp_folder\$reportsFolder.zip"
            }else{
                Copy-Item "C:\EP40\C$bin\REPORTS\OUTGOING\$reportsFolder.zip" "C:\EP40\C$bin\REPORTS\OUTGOING\jenkins\$reportsFolder.zip"
            }
            
            Remove-Item -LiteralPath "C:\EP40\C$bin\REPORTS\OUTGOING\$reportsFolder" -Force -Recurse
         }
    }

    move-item -Path "C:\EP40\C$bin\REPORTS\OUTGOING\*.zip" -Destination "C:\EP40\C$bin\REPORTS\OUTGOING\$year" -Force

    # restore initial path
    set-location $path

    }
Function pp_ardef{
    $path=$(get-location).path
    set-location "C:\EP40\C$bin\ARDEF\"
    $file=gci * -file -include "EPArdefExt_.TXT" -name 
    $date1=get-date -format "yyyyMMdd"

    log -text "INFO [$bin $runType] Moving & renaming EPArdefExt_.TXT."

    if($file){
        copy-item $file "C:\EP40\C439747\ARDEF\jenkins\EpArdefExt_$date1.txt" -Force
        remove-item "C:\EP40\C$bin\ARDEF\$file"
    }else{
        log -text "ERROR [$bin $runType] EPArdefExt_.TXT does not exist."
    }

    set-location $path
    }
Function cleanup{
    $filesToClean=gci C:\EP40\workspace\*.txt -include "VI*EPIN.TXT", "EPIN_BPCPS*TXT","SAVE.INCOMING*EPIN.TXT","EPArdefExt_*.txt" | where-object{$_.lastaccesstime -lt (get-date).adddays(-3)}
    if($filesToClean){
        log -text "INFO [$bin $runType] Removing $filesToClean."
        $filesToClean | %{remove-item $_}
        }
    }


# PARAMETERS
$BFLocation="C:\EP40\BatchFacility"
$semaphoreFile="$BFLocation\semaphore.txt"
$pgmStartTime=get-date


log -text ""
log -text "INFO [$bin $runType] @START@." 

$batchFolder=validate-inputParameters

create-logFile

create-semaphore

check-EditPackage

call-batchFacility

check-resultAndCallPostProcess

remove-semaphore 

cleanup

log -text "INFO [$bin $runType] @END@."



<# 
WIN SCHEDULER CONFIG:
    PROGRAM/PARANCSFILE:
        C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
    ARGUMENTUMOK:
        -command "& C:\EP40\BatchFacility\EP.ps1 -bin 483635 -runType inc"
    INDÍTÁS HELYE:
        C:\EP40\BatchFacility
#>
