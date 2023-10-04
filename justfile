# We're doing lots of local builds, take advantage of some caching
force_nocache := "false"

comps-sync:
    #!/bin/bash
    set -euxo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

manifest compose_file:
    #!/bin/bash
    set -euxo pipefail

    yq -y . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}})

packages compose_file:
    #!/bin/bash
    set -euxo pipefail

    echo "packages:"
    yq -y . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}} | jq .packages)

prep:
    #!/bin/bash
    set -euxo pipefail

    mkdir -p repo cache
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=archive
        popd > /dev/null || exit 1
    fi

    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

dry-run compose_file:
    #!/bin/bash
    set -euxo pipefail

    export LC_COLLATE="C"

    VARIANT=$(echo "{{compose_file}}" | sed -re 's/\.yaml$//')

    ARGS="--unified-core --cachedir=cache --repo=repo --dry-run"

    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=" --force-nocache"
    fi

    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose tree ${ARGS} {{compose_file}} \
        | grep '^  ' | sed -re 's/^\s+//' -e 's/\ (.*)$//' -e 's/\.fc39.*//' \
            > packages.${VARIANT}

    if [[ ${EUID} -ne 0 ]]; then
        sudo chown --recursive "$(id --user --name):$(id --group --name)" repo cache
    fi
