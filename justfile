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

    just fix-perms

registry:
    podman run --rm --detach --pull always --publish 5000:5000 --volume ~/docker-registry:/var/lib/registry --name registry registry:latest || true

compose-image compose_file:
    #!/bin/bash
    set -euxo pipefail

    just prep
    just registry

    VARIANT=$(echo "{{compose_file}}" | sed -re 's/\.yaml$//')

    ARGS="--cachedir cache --format=registry --initialize-mode=if-not-exists"

    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=" --force-nocache"
    fi

    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose image ${ARGS} {{compose_file}} "localhost:5000/fedora-${variant}"

    just fix-perms

layer-image:
    just registry

    podman build --tag fedora-test --file Containerfile
    podman push localhost/fedora-test localhost:5000/fedora-test

fix-perms:
    #!/bin/bash
    set -euxo pipefail

    if [[ ${EUID} -ne 0 ]]; then
        sudo chown --recursive "$(id --user --name):$(id --group --name)" cache repo
    fi
