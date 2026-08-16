# Contributing to Kubling Samples

This repository is a runnable companion to the Kubling documentation. Changes should make a sample easier to understand, reproduce, and validate.

## Scope

A sample belongs here when it does at least one of the following:

- provides the canonical first-run experience for Kubling; or
- demonstrates a Kubling feature whose behavior is not obvious from reference documentation alone.

Large vendor integrations, infrastructure demonstrations, generated clients, and general-purpose application examples belong in dedicated repositories or external guides.

## Sample contract

Prefer this structure for each independently runnable sample:

```text
sample-name/
├── README.md
├── compose.yaml
├── config/
├── descriptor/
├── modules/
└── scripts/
```

Only include directories the sample actually needs. Its README must state:

- the single capability being demonstrated;
- prerequisites and exact supported versions;
- how to start it;
- how to determine that it is ready;
- one or more verification commands;
- deterministic expected results;
- exposed ports and health endpoints;
- how to stop it and remove its state; and
- any limitation that prevents automated end-to-end validation.

## Legacy references

Some directories are temporarily retained as source material because they contain useful examples of advanced Kubling behavior. Their README starts with a `Legacy reference` warning.

A legacy reference is not a supported deployment recipe. Do not remove its warning until the sample satisfies this contribution contract, uses the current provider architecture where applicable, and has been validated against its declared Kubling version. Modernize one capability at a time instead of preserving a large historical scenario unchanged.

## Providers and JavaScript

Examples that demonstrate a data provider must register it as `PROVIDER_GRPC` and use a separately running provider image. Provider-owned physical schema must be imported through the provider contract rather than duplicated in the VDB descriptor.

JavaScript adapters remain valid when JavaScript behavior is the subject of the sample, for example custom functions, endpoints, policies, or orchestration. State that choice explicitly in the sample README so it is not mistaken for the provider integration pattern.

## Generated files

Do not commit generated or runtime artifacts, including:

- descriptor and module ZIP bundles;
- JAR and class files;
- database files and journals;
- logs, process IDs, and runtime-generated configuration; or
- tool-specific build directories.

Commit the source needed to reproduce an artifact. If a sample needs a bundle, its documented workflow must generate it locally. The canonical quickstart must do this with pinned container images so it does not add a host-language toolchain prerequisite.

## Versions and images

- Pin Kubling and provider images in supported samples to exact release versions.
- Do not introduce `latest` or an untagged image reference. Remove inherited uses when modernizing a legacy reference.
- Prefer a digest in the canonical quickstart after official release digests are confirmed.
- Keep the compatible Kubling version visible in the sample README.

## Credentials and local configuration

Never commit credentials, access tokens, private endpoints, or populated `.env` files. Document required variables in `.env.example` only when a focused sample genuinely needs them.

## Validation

Run the repository checks before submitting a change:

```bash
bash scripts/check-repository.sh
```

Also run the sample-specific validation documented in its README. A syntax or configuration check is not a substitute for an end-to-end test; state precisely what was verified.

## Change size

Keep changes small and reviewable. Repository-wide cleanup, sample selection, and sample modernization should be separate changes whenever possible.
