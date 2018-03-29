# 2.0.0 / 2018-03-29
## Deps
- Update pg dependency to ^7.
## Other
- Changes internals to explicitly create a pg.Pool(...) rather than relying on pg.connect(...) to handle it.
