# Changelog

## [0.4.0](https://github.com/bcit-tlu/redirect-service/compare/v0.3.1...v0.4.0) (2026-09-17)


### Features

* move delay_seconds into mappings.env as a directive line ([bfa8d6e](https://github.com/bcit-tlu/redirect-service/commit/bfa8d6e5d7811c6e96c3747b4c0bbd86141ec894))

## [0.3.1](https://github.com/bcit-tlu/redirect-service/compare/v0.3.0...v0.3.1) (2026-09-17)


### Bug Fixes

* **chart:** serve REDIRECT_DELAY_SECONDS as a mounted file, not env ([27d2620](https://github.com/bcit-tlu/redirect-service/commit/27d26201c22518e22d6f7c4a8bf0e9182d8c6e71))

## [0.3.0](https://github.com/bcit-tlu/redirect-service/compare/v0.2.0...v0.3.0) (2026-09-17)


### Features

* add mappings.env as the built-in default redirect table ([5ce144c](https://github.com/bcit-tlu/redirect-service/commit/5ce144c9cabf6036c10b1764c958857e53c554c7))
* **chart:** move mappings into a ConfigMap ([83dab04](https://github.com/bcit-tlu/redirect-service/commit/83dab0486880d50a7f0a9e9ffc479e6d4e62d630))
* live-reload mapping file; sanitize service for reuse ([c47268f](https://github.com/bcit-tlu/redirect-service/commit/c47268f3fc6d2db5db47986ce726ba3987dc08e0))


### Bug Fixes

* **image:** strip cap_net_bind_service from caddy binary ([28269c2](https://github.com/bcit-tlu/redirect-service/commit/28269c2070760ef004a4c533732591d805cd9de2))
* updates index.html ([5b3fd78](https://github.com/bcit-tlu/redirect-service/commit/5b3fd788aa0775b0b6649fa7a0513262dff222e6))

## [0.2.0](https://github.com/bcit-tlu/redirect-service/compare/v0.1.0...v0.2.0) (2026-09-17)


### Features

* add Caddy migration-redirect splash service ([75d17c8](https://github.com/bcit-tlu/redirect-service/commit/75d17c8824c8d9329f741cf73408f2fb9bee1553))
* **chart:** add optional Ingress template ([ab55da9](https://github.com/bcit-tlu/redirect-service/commit/ab55da933b4a1d10dc4368e3e6845d431260cb75))
* **ci:** add release-please and release publish workflows ([f4ab9f2](https://github.com/bcit-tlu/redirect-service/commit/f4ab9f20d5bdc254bddeaf5e07048978b6a49ff3))


### Bug Fixes

* **chart:** correct image repository path ([d20546a](https://github.com/bcit-tlu/redirect-service/commit/d20546aacf6cca3154ea855ea65851deecbbde44))
* edits README.md ([5d996e2](https://github.com/bcit-tlu/redirect-service/commit/5d996e263c1dfcb14277c81ebb63d674a846f659))
