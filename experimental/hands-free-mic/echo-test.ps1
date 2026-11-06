# Records the mic two ways (with and without echo cancelling) while Ava talks,
# then transcribes both so we can see whether Ava's voice leaked in.
$dir = "$env:USERPROFILE\.claude\voice"
$aec = Join-Path $dir 'test-aec.wav'; $raw = Join-Path $dir 'test-raw.wav'
Remove-Item $aec, $raw -ErrorAction SilentlyContinue

Add-Type -Namespace W -Name M -MemberDefinition '[DllImport("winmm.dll", CharSet=CharSet.Unicode)] public static extern int mciSendString(string c, System.Text.StringBuilder r, int l, IntPtr h);'
function Mci($c) { [void][W.M]::mciSendString($c, $null, 0, [IntPtr]::Zero) }

$p = Start-Process "$dir\EchoCancelMic.exe" -ArgumentList "`"$aec`"", 55 -WindowStyle Hidden -PassThru
Mci 'open new type waveaudio alias rec'
Mci 'set rec bitspersample 16 samplespersec 16000 channels 1'
Mci 'record rec'
Start-Sleep 2

$script = 'Echo test, part one. Please stay quiet while I read this. I am going to keep talking for a little while, so the microphone hears plenty of my voice. If the echo filter works, none of these words should show up in the filtered recording. ' +
          'Part two. Now please talk over me. Say anything you like, for example count slowly from one to ten, while I keep reading. The quick brown fox jumps over the lazy dog. She sells sea shells by the sea shore. Peter Piper picked a peck of pickled peppers. How much wood would a woodchuck chuck. ' +
          'Test complete. You can stop talking now.'
$inbox = "$env:TEMP\claude-voice\inbox"
[IO.File]::WriteAllText("$inbox\$([DateTime]::UtcNow.Ticks).say", $script, [Text.UTF8Encoding]::new($false))

$p.WaitForExit()
Mci 'stop rec'; Mci "save rec `"$raw`""; Mci 'close rec'
& "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe" -I "$dir\transcribe.py" $raw $aec
