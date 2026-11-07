# Unreleased changelog fragments

One YAML file per change, named for its issue (`c-834.yaml`), same categories as `../versions/*.yaml`:

```yaml
bug:
  - "Fixed ``TeakFoo`` when bar."
```

`yarn changelog check` validates them. At release, `yarn changelog roll <version>` merges them into
`../versions/<version>.yaml` and deletes them.
