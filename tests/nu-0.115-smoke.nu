use std/assert

def test-yaml-contracts [] {
    assert equal ('yes' | from yaml) 'yes'
    assert equal ('yes' | from yaml --spec 1.1) true
    assert equal ('0247' | from yaml) 247
    assert equal ('0247' | from yaml --spec 1.1) 0o247

    assert error { 'true: enabled' | from yaml }

    let verbatim = ('true: enabled' | from yaml --key-resolution verbatim)
    assert equal ($verbatim | columns) ['true']
    assert equal ($verbatim | values) ['enabled']

    assert error { 'Key: !Sub ${AWS::StackName}' | from yaml }
    assert equal (
        'Key: !Sub ${AWS::StackName}'
        | from yaml --ignore-tags
        | get Key
    ) '${AWS::StackName}'

    assert equal ('name: dev' | from yaml --multiple list) [{name: dev}]
    assert error { "name: dev\n---\nname: prod" | from yaml --multiple single }
    assert error { {|| $in } | to yaml }
}

def test-high-frequency-commands [] {
    assert ([9 8 7 6] | enumerate | any item == index * 2)
    assert ([1sec 1min 1hr] | all ($it | describe) == duration)

    assert equal (
        0x[01 02 03 04]
        | chunks 2b
        | each { encode hex }
    ) ['0102' '0304']

    # Keep each comparison in an unconstrained list and extract it immediately.
    # In 0.115.0, direct bool contexts and typed/untyped `let` assignments can
    # infer `semver` even though the runtime value is bool.
    assert equal ([
        (('2.0.1' | into semver) > '1.9.9')
    ] | first) true
    assert equal ([
        (('1.0.0-alpha' | into semver) < '1.0.0')
    ] | first) true
    let loose_versions = (['v1.2.3' 'v2.0.0'] | into semver --loose)
    assert equal ($loose_versions | each { describe }) [semver semver]
    assert equal (
        $loose_versions | each { into string }
    ) ['v1.2.3' 'v2.0.0']

    assert equal (
        [1 2 3 4]
        | take until {|value| $value == 3 } --include 1
    ) [1 2 3]
    assert equal (
        [1 2 3 4]
        | take while {|value| $value < 3 } --include 1
    ) [1 2 3]
}

def test-correctness-fixes [] {
    let groups = ([a '' null] | group-by --to-table)
    assert equal ($groups | length) 3
    assert equal $groups.0.group a
    assert equal $groups.1.group ''
    assert equal $groups.2.group null

    let record_groups = ([a '' null] | group-by)
    assert equal ($record_groups | columns) [a '']

    assert equal ('' | path type) null
    assert error { error make {msg: 'bad label', label: {text: 'missing span'}} }

    let deprecated = (
        scope commands
        | where name == 'str downcase'
        | first
        | get deprecation_info
    )
    assert ($deprecated | is-not-empty)
}

def test-external-arg [] {
    let fixture_root = (mktemp --directory)

    try {
        let script = ($fixture_root | path join 'external-arg.nu')
        r#'def main [
    first: external_arg
    second: external_arg
    ...rest: external_arg
] {
    {
        first: ($first | into string)
        first_type: ($first | describe)
        second: ($second | into string)
        second_type: ($second | describe)
        rest: ($rest | each { into string })
    } | to json --raw
}
'# | save --force $script

        let result = (^nu --no-config-file $script 0001 true -- 001 | complete)
        assert equal $result.exit_code 0
        assert equal ($result.stderr | str trim) ''

        let parsed = ($result.stdout | from json)
        assert equal $parsed.first '0001'
        assert equal $parsed.first_type glob
        assert equal $parsed.second 'true'
        assert equal $parsed.second_type glob
        assert equal $parsed.rest ['001']

        let command_result = (
            ^nu --no-config-file -c r#'def main [value: external_arg] {
    {value: ($value | into string), type: ($value | describe)} | to json --raw
}'# -- 0001
            | complete
        )
        assert equal $command_result.exit_code 0
        assert equal ($command_result.stderr | str trim) ''
        assert equal ($command_result.stdout | from json) {
            value: '0001'
            type: glob
        }
    } finally {
        rm -r -f $fixture_root
    }
}

def main [] {
    test-yaml-contracts
    test-high-frequency-commands
    test-correctness-fixes
    test-external-arg
    print 'nu-0.115-smoke: ok'
}
