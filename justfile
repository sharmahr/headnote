set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

# See AGENTS.md §3.
check: fmt-check clippy test deny

fmt-check:
    cargo fmt --all --check

clippy:
    cargo clippy --workspace --all-targets --locked -- -D warnings

test:
    cargo build --workspace --bins --locked
    cargo test --workspace --locked

deny:
    cargo deny --locked check
