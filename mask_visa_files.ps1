
function mask_card{
    param (
        [String]$card
    )
    $card_length=$($card.Trim()).length
    $card_left=$card.Substring(0,6)
    $card_right=$card.Substring($card_length-3)
    $mask="*"*[int]$($card_length-9)
    $masked_card="$card_left$mask$card_right"
    $final_card=$masked_card.PadRight(19," ")
    return $final_card
}

function mask_epin_file{
    param (
        [String]$file
    )
    $ofile=$file
    $ifile=$file.Replace("EPIN.txt","EPIN_WRK_.txt")

    Rename-Item $file $ifile

    gc $ifile | %{
        if($_ -like "33*"){
            if($_.substring(34,6) -eq "V22200"){
                $card=$_.substring(130,19)
                $masked_card=mask_card -card $card
                $_.replace($card,$masked_card)| Out-File $ofile -Encoding ascii -Append
            }else{
                $_ | Out-File $ofile -Encoding ascii -Append
            }
        }elseif($_ -like "45*"){
            if($_.substring(14,3) -eq "820"){
                if($_.substring(36,19) -match '^\d{16}'){
                    $card=$_.substring(36,19)
                    $masked_card=mask_card -card $card
                    $_.replace($card,$masked_card)| Out-File $ofile -Encoding ascii -Append
                }else{
                    $_ | Out-File $ofile -Encoding ascii -Append
                }
            }else{
                $_ | Out-File $ofile -Encoding ascii -Append
            }

        }else{
            $_ | Out-File $ofile -Encoding ascii -Append
        }

    }
    Remove-Item $ifile -force
}

function mask_EP745_file{
    param (
        [String]$file
    )
    $ofile=$file
    $ifile=$file.Replace("EP745.txt","EP745_WRK_.txt")

    Rename-Item $file $ifile

    gc $ifile | %{
        if($_ -like "  *" -and $_.substring(2,1) -ne " " `
        -and $_.substring(13,1) -eq ":" ){
            $card=$_.substring(20,19)
            $masked_card=mask_card -card $card
            $_.replace($card,$masked_card) | Out-File $ofile -Encoding ascii -Append
        }else{
             $_ | Out-File $ofile -Encoding ascii -Append
        }
    }
    Remove-Item $ifile -Force
}

function mask_EP733_file{
    param (
        [String]$file
    )
    $ofile=$file
    $ifile=$file.Replace("EP733.txt","EP733_WRK_.txt")

    Rename-Item $file $ifile

    gc $ifile | %{
        if($_ -like "*33*V22200*"){
            $next=$True
            $_ | Out-File $ofile -Encoding ascii -Append
        }elseif($next){
            $card=$_.substring(55,19)
            $masked_card=mask_card -card $card
            $_.replace($card,$masked_card) | Out-File $ofile -Encoding ascii -Append
            $next=$False
        }else{
            $_ | Out-File $ofile -Encoding ascii -Append
        }
    }

    Remove-Item $ifile -Force
}

$work_folder="C:\Users\fazakas\Downloads\visa_mask"
sl $work_folder
mask_epin_file -file "EPIN.txt"
mask_ep745_file -file "EP745.txt"
mask_EP733_file -file "EP733.txt"
