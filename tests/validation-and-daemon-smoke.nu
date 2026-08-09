use std/assert

def ide-check [script: path] {
    # A missing target also exits 0 with no output, so it must fail early here.
    if not ($script | path exists) {
        error make {msg: $"ide-check target not found: ($script)"}
    }

    let result = (^nu --no-config-file --ide-check 100 $script | complete)
    let messages = (
        $result.stdout
        | lines
        | where {|line| not ($line | str trim | is-empty) }
        | each {|line| $line | from json }
    )
    let errors = (
        $messages
        | where {|message|
            (($message.type? | default '') == 'diagnostic') and (($message.severity? | default '') == 'Error')
        }
    )
    let warnings = (
        $messages
        | where {|message|
            (($message.type? | default '') == 'diagnostic') and (($message.severity? | default '') != 'Error')
        }
    )

    {result: $result, messages: $messages, errors: $errors, warnings: $warnings}
}

def wait-until [
    predicate: closure
    --timeout: duration = 5sec
    --interval: duration = 50ms
] {
    let deadline = ((date now) + $timeout)

    loop {
        if (do $predicate) {
            return
        }

        if (date now) >= $deadline {
            error make {msg: $"Readiness deadline exceeded after ($timeout)"}
        }

        sleep $interval
    }
}

def main [] {
    let fixture_root = (mktemp --directory)

    try {
        let hint_script = ($fixture_root | path join 'hint.nu')
        let error_script = ($fixture_root | path join 'error.nu')

        r#'let value = 42
$value | ignore
'# | save --force $hint_script

        r#'let value: int = "text"
$value | ignore
'# | save --force $error_script

        assert error { ide-check ($fixture_root | path join 'missing.nu') }

        let hint_check = (ide-check $hint_script)
        assert equal $hint_check.result.exit_code 0
        assert ($hint_check.errors | is-empty)
        assert ($hint_check.warnings | is-empty)
        assert ($hint_check.messages | any {|message| $message.type? == 'hint' })

        let error_check = (ide-check $error_script)
        assert equal $error_check.result.exit_code 0
        assert not ($error_check.errors | is-empty)

        let state_dir = ($fixture_root | path join 'state')
        let temp_dir = ($fixture_root | path join 'tmp')
        let ready_file = ($state_dir | path join 'ready.json')
        mkdir $temp_dir

        let job_id = (with-env {
            NUSHELL_PRO_SMOKE_STATE: $state_dir
            TMPDIR: $temp_dir
        } {
            job spawn --description 'nushell-pro daemon smoke fixture' {
                mkdir $env.NUSHELL_PRO_SMOKE_STATE
                {
                    status: 'ready'
                    state_dir: $env.NUSHELL_PRO_SMOKE_STATE
                    temp_dir: $env.TMPDIR
                }
                | to json
                | save --force ($env.NUSHELL_PRO_SMOKE_STATE | path join 'ready.json')

                ^nu --no-config-file -c 'loop { sleep 1sec }'
            }
        })

        let child_pids = (try {
            wait-until {
                let rows = (job list | where id == $job_id)
                if ($rows | is-empty) {
                    error make {msg: 'Background job stopped before readiness'}
                }

                let job = ($rows | first)
                ($ready_file | path exists) and not ($job.pids | is-empty)
            } --timeout 3sec

            let job = (job list | where id == $job_id | first)
            assert equal $job.description 'nushell-pro daemon smoke fixture'

            let ready = (open $ready_file)
            assert equal $ready.status 'ready'
            assert equal $ready.state_dir $state_dir
            assert equal $ready.temp_dir $temp_dir

            $job.pids
        } finally {
            try { job kill $job_id }
        })

        wait-until {
            not ($job_id in (job list | get id))
        } --timeout 2sec

        assert not ($child_pids | is-empty)
        for pid in $child_pids {
            wait-until {
                ps | where pid == $pid | is-empty
            } --timeout 3sec
        }

    } finally {
        rm -r -f $fixture_root
    }

    assert (not ($fixture_root | path exists))
    print 'validation-and-daemon-smoke: ok'
}
