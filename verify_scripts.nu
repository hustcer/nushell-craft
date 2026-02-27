def check-nu-blocks [file: string] {
  let lines = (open $file | lines)
  mut blocks = []
  mut current_block = ""
  mut in_block = false

  for line in $lines {
    if ($line | str starts-with "```nu") {
      $in_block = true
      $current_block = ""
    } else if ($line | str starts-with "```") and $in_block {
      $in_block = false
      $blocks = ($blocks | append {file: $file, code: ($current_block | str trim)})
    } else if $in_block {
      $current_block = ($current_block + $line + "\n")
    }
  }

  mut results = []
  for bk in $blocks {
    let code = $bk.code
    if ($code | is-empty) { continue }

    let is_err = (try {
      let ast_out = (ast $code)
      if ($ast_out.error | str contains "Some") {
        $ast_out.error
      } else {
        "ok"
      }
    } catch { |e| $e.msg })

    if $is_err != "ok" {
      $results = ($results | append {file: $bk.file, code: $code, error: $is_err})
    }
  }
  $results
}

let files = (glob "**/*.md")
mut all_errors = []
for f in $files {
  let errs = (check-nu-blocks $f)
  $all_errors = ($all_errors | append $errs)
}
$all_errors | to json | save -f errors.json
