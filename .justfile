
# show this help
@help:
  just --list --unsorted

# build kmods container
kmod-build:
    podman build --no-cache --pull --build-arg FEDORA_VERSION=39 --tag fedora-kmods:39 --file Containerfile.fedora-kmods

# test kmod build
kmod-test: kmod-build
    just container-list fedora-kmods:39

# list contents of container image
container-list container:
    podman image save {{container}} | tar --extract --to-stdout --exclude layer.tar '*.tar' | tar --list --verbose




build *ARGS:
  podman build --file Containerfile.builder --tag fedora-nvidia-latest:39 {{ARGS}}

run:
  podman run --rm -it --privileged --workdir /build --volume ./rpms:/rpms fedora-builder:39








# We're doing lots of local builds, take advantage of some caching
force_nocache := "false"

# podman image save ghcr.io/ublue-os/akmods:main-39 | tar xv --to-stdout '*.tar' --exclude layer.tar | tar xv



# fetch updated official fedora comps
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

# print out the manifest resolving all includes
manifest compose_file:
    yq --output-format=yaml --prettyPrint . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}})

# print out just packages from manifest
packages compose_file:
    yq --output-format=yaml --prettyPrint '.packages' <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}})

# prepare folders for rpm-ostree compose
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

# perform a dry-run to depsolve package list
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

# compose an image uploading directly to localhost:5000/${variant}
compose-image compose_file:
    #!/bin/bash
    set -euxo pipefail

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

# compose an image with interim ${variant}.ociarchive then copy to localhost:5000/${variant}
compose-archive compose_file:
    #!/bin/bash
    set -euxo pipefail

    just prep
    just registry

    variant=$(echo "{{compose_file}}" | sed -re 's/\.yaml$//')

    ARGS="--cachedir cache --format=ociarchive --initialize"
    [[ {{force_nocache}} == "true" ]] && ARGS+=" --force-nocache"

    CMD="rpm-ostree"
    [[ ${EUID} -ne 0 ]] && CMD="sudo rpm-ostree"

    ${CMD} compose image ${ARGS} {{compose_file}} ${variant}.ociarchive

    sudo chown "$(id --user --name):$(id --group --name)" ${variant}.ociarchive

    skopeo copy oci-archive:fedora-minimal.ociarchive docker://localhost:5000/${variant}

    just fix-perms

# fix permissions of local directories if commands have been run with sudo instead of inside a podman container
fix-perms:
    #!/bin/bash
    set -euxo pipefail

    if [[ ${EUID} -ne 0 ]]; then
        fd --no-ignore --owner root --exec sudo chown "$(id --user --name):$(id --group --name)" {}
    fi

# start a basic local docker registry
registry:
    #!/bin/bash
    set -euxo pipefail

    podman container inspect registry >/dev/null 2>&1 || podman run --rm --detach --pull always --publish 5000:5000 --volume ~/docker-registry:/var/lib/registry --name registry registry:latest

# enter a podman build  env
podman:
    podman run --pull=newer --rm -ti --volume $PWD:/srv:rw --workdir /srv --privileged quay.io/fedora-ostree-desktops/buildroot
