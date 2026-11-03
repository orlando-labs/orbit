<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <title>#{title}</title>
    #{json_script(bootstrap, id: "orbit-bootstrap")}
    #{assets.tags(entry: entry)}
  </head>
  <body>
    <header class="shell-header">
      <a class="wordmark" href="/" aria-label="Orbit home"><span class="orbit-mark" aria-hidden="true">◌</span> orbit</a>
      <span class="shell-label">Vue application preview</span>
    </header>
    <main>#{content}</main>
    <footer class="shell-footer"><span>Sputnik backend · Vue frontend</span><span>Account preview / 01</span></footer>
  </body>
</html>
