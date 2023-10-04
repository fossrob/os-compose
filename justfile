
manifest compose_file:
  yq -y . <<<$(rpm-ostree compose tree --print-only --repo=repo {{compose_file}})
