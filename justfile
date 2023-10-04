
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
  yq -y . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}})
