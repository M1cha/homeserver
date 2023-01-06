# std2pipe

Routes stdout and stderr of a process through pipes.

This is needed if stdout is e.g. a socket and the process tries to use
`/dev/stdout` or `/dev/stdout`. https://github.com/envoyproxy/envoy/issues/8297

# Usage

Syntax:

```bash
std2pipe COMMAND ARG...
```

Example:

```bash
std2pipe echo hello
```
