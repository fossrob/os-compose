FROM ghcr.io/fossrob/fedora-custom:latest

ADD https://copr.fedorainfracloud.org/coprs/ublue-os/akmods/repo/fedora-39/ublue-os-akmods-fedora-39.repo \
      /etc/yum.repos.d/ublue-os-akmods-fedora-39.repo

# COPY scripts/* /tmp/

# RUN for repo in $(ls /etc/yum.repos.d/*.repo); do sed -i $repo -e 's/enabled=1/enabled=0/'; done

# COPY fedora-all.repo /etc/yum.repos.d/

# vera family: BitstreamVeraSansMono DejaVuSansMono Hack`
# other nerd fonts: CodeNewRoman DroidSansMono FiraCode InconsolataGo LiberationMono Noto RobotoMono SourceCodePro NerdFontsSymbolsOnly UbuntuMono

# RUN echo "Installing Fonts..." && \
#       # inter
#       mkdir -p /usr/share/fonts/inter && \
#       curl --silent --remote-name --output-dir /tmp --location "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip" && \
#       unzip /tmp/Inter-3.19.zip 'Inter Variable/*' -d /usr/share/fonts/inter && \
#       # robotomono
#       mkdir -p /usr/share/fonts/nerd-fonts/robotomono && \
#       curl --silent --remote-name --output-dir /tmp --location "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/RobotoMono.tar.xz" && \
#       pushd "/usr/share/fonts/nerd-fonts/robotomono" || exit && \
#       tar --extract --xz --verbose --file "/tmp/RobotoMono.tar.xz" '*.ttf' && \
#       popd || exit && \
#       # regenerate cache
#       fc-cache --really-force && \
#     echo "...done!"

# ADD https://download.opensuse.org/repositories/hardware:/razer/Fedora_39/hardware:razer.repo \
#       /etc/yum.repos.d/razer.repo

COPY --from=ghcr.io/fossrob/kmods:39 / .

RUN echo "Installing kmods..." && \
      rpm-ostree install /rpms/kmod-*.rpm nvidia-vaapi-driver && \
    echo "...done!"

RUN echo "Customising packages & services..." && \
      # mkdir -p /var/lib/alternatives && \
      rpm-ostree install --idempotent \
        NetworkManager-openvpn-gnome \
        bat fd-find fzf the_silver_searcher \
        code \
        fastfetch \
        kitty \
        libva-utils \
        lshw \
        openssl \
        powertop \
        python3-pip python3-pyyaml \
        starship \
        subscription-manager \
        tlp tlp-rdw \
        virt-manager \
        wl-clipboard \
        xeyes \
      && \
    echo "...done!"

RUN echo "Clean up and commit..." && \
      rm -rf /tmp/* /var/* && \
      ostree container commit && \
    echo "...done!"
