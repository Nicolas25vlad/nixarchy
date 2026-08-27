Screenshots of the running desktop, captured with ../capture-screenshots.sh.
They need a graphical VM: with -display none nothing consumes the compositor's
frames and grim blocks forever.

17-plugins-menu.jpg and 18-plugins-bar.jpg are the exception: they come from
`nix build .#checks.x86_64-linux.plugin`, which installs two real third-party
plugins and screenshots the result. That check runs headless -- its frames come
from qemu's screendump rather than grim -- and it is the only place where two
plugins are installed and enabled at once, which is what the bar strips show.
