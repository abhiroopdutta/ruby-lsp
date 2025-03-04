# Editors

This file contains community driven instructions on how to set up the Ruby LSP in editors other than VS Code. For VS
Code, use the official [Ruby LSP extension](https://github.com/Shopify/vscode-ruby-lsp).

<!-- When adding a new editor to the list, either link directly to a website containing the instructions or link to a
new H2 header in this file containing the instructions. -->

- [Emacs LSP Mode](https://emacs-lsp.github.io/lsp-mode/page/lsp-ruby-lsp/)
- [Emacs Eglot](#Emacs-Eglot)

## Emacs Eglot

[Eglot](https://github.com/joaotavora/eglot) runs solargraph server by default. To set it up with ruby-lsp you need to put that in your init file:
```el
(with-eval-after-load 'eglot
 (add-to-list 'eglot-server-programs '((ruby-mode ruby-ts-mode) "ruby-lsp")))
 ```
Or if you want to run it with bundler:
```el
(with-eval-after-load 'eglot
 (add-to-list 'eglot-server-programs '((ruby-mode ruby-ts-mode) "bundle" "exec" "ruby-lsp")))
```
 
When you run `eglot` command it will run `ruby-lsp` process for you.
