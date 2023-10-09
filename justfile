# We're doing lots of local builds, take advantage of some caching
force_nocache := "false"

# podman image save ghcr.io/ublue-os/akmods:main-39 | tar xv --to-stdout '*.tar' --exclude layer.tar | tar xv

container-list container:
    podman pull --quiet {{container}}
    podman image save {{container}} | tar --extract --to-stdout --exclude layer.tar '*.tar' | tar --list --verbose

comps-sync:
    #!/bin/bash
    set -euo pipefail

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
    set -euo pipefail

    yq -y . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}})

packages compose_file:
    #!/bin/bash
    set -euo pipefail

    echo "packages:"
    yq -y . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}} | jq .packages)

prep:
    #!/bin/bash
    set -euo pipefail

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
    set -euo pipefail

    export LC_COLLATE="C"

    variant=$(echo "{{compose_file}}" | sed -re 's/\.yaml$//')

    ARGS="--unified-core --cachedir=cache --repo=repo --dry-run"
    [[ {{force_nocache}} == "true" ]] && ARGS+=" --force-nocache"

    CMD="rpm-ostree"
    [[ ${EUID} -ne 0 ]] && CMD="sudo rpm-ostree"

    ${CMD} compose tree ${ARGS} {{compose_file}} \
        | grep '^  ' | sed -re 's/^\s+//' -e 's/\ (.*)$//' -e 's/\.fc39.*//' \
            > packages.${variant}

    if [[ -f packages.${variant}.before ]]; then
        ADDED=$(comm -13 packages.${variant}.before packages.${variant})
        REMOVED=$(comm -23 packages.${variant}.before packages.${variant})
        if [[ -n "$ADDED" ]]; then
            echo "Packages added:" $(echo "$ADDED" | wc -l)
            echo "$ADDED" | sed -re 's/^/  /'
        fi
        if [[ -n "$REMOVED" ]]; then
            echo "Packages removed:" $(echo "$REMOVED" | wc -l)
            echo "$REMOVED" | sed -re 's/^/  /'
        fi
    fi

    just fix-perms

compose-image compose_file:
    #!/bin/bash
    set -euo pipefail

    just prep
    just registry

    variant=$(echo "{{compose_file}}" | sed -re 's/\.yaml$//')

    # ARGS="--cachedir cache --format=registry --initialize-mode=if-not-exists"

    ARGS="--cachedir cache --format=registry --initialize-mode=always"
    [[ {{force_nocache}} == "true" ]] && ARGS+=" --force-nocache"

    CMD="rpm-ostree"
    [[ ${EUID} -ne 0 ]] && CMD="sudo rpm-ostree"

    ${CMD} compose image ${ARGS} {{compose_file}} "localhost:5000/${variant}"

    just fix-perms

compose-archive compose_file:
    #!/bin/bash
    set -euo pipefail

    just prep
    just registry

    variant=$(echo "{{compose_file}}" | sed -re 's/\.yaml$//')

    ARGS="--cachedir cache --format=ociarchive --initialize"
    [[ {{force_nocache}} == "true" ]] && ARGS+=" --force-nocache"

    CMD="rpm-ostree"
    [[ ${EUID} -ne 0 ]] && CMD="sudo rpm-ostree"

    ${CMD} compose image ${ARGS} {{compose_file}} ${variant}.ociarchive

    skopeo copy oci-archive:fedora-minimal.ociarchive docker://localhost:5000/${variant}

    just fix-perms

layer-image container_file:
    #!/bin/bash
    set -euo pipefail

    just registry

    container_tag=$(echo "{{container_file}}" | sed -re 's/^Containerfile\.//')

    podman build --tag fedora-test:${container_tag} --file {{container_file}}
    podman push fedora-test:${container_tag} localhost:5000/fedora-test:${container_tag}

fix-perms:
    #!/bin/bash
    set -euo pipefail

    if [[ ${EUID} -ne 0 ]]; then
        fd --no-ignore --owner root --exec sudo chown "$(id --user --name):$(id --group --name)" {}
    fi

registry:
    #!/bin/bash
    set -euo pipefail

    podman container inspect registry >/dev/null 2>&1 || podman run --rm --detach --pull always --publish 5000:5000 --volume ~/docker-registry:/var/lib/registry --name registry registry:latest
