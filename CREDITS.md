# Credits

## ps-dispatch

Original authors: **Project Sloth & OK1ez**
Upstream project: <https://github.com/Project-Sloth/ps-dispatch>

ps-dispatch is licensed under the **GNU General Public License v3.0**. This
repository is a derivative work of it and is distributed under that same
license — see [`LICENSE`](LICENSE) for the full text, and [`CHANGES.md`](CHANGES.md)
for what was modified here and when.

All of the dispatch system itself — the alert pipeline, the NUI, the call
board, plate log, major incidents, and every export other resources call — is
their work. The changes in this fork are limited to adding a framework bridge.

## ESX Legacy bridge

Contributed by **RNGD-Development**. Adds ESX Legacy support alongside the
existing QBCore/QBX support, as an additive bridge layer.

## Sixxenik

<https://github.com/Sixxenik/ps-dispatch-esx>

Credited for **one specific idea**, and nothing more: resolving an ESX
character's first and last name by querying the stock `users` table directly
(`SELECT firstname, lastname FROM users WHERE identifier = ?`) rather than
relying on the name being present on the ESX player object, which depends on
which identity resource a server runs.

To be precise about the scope of this credit: **no code from that fork is used
in this repository.** The bridge here was written from scratch against this
codebase's own conventions. Their fork also contains couplings to the author's
own private resources that are deliberately not reproduced here.
