# Orbit for Sputnik Notebook

Select `slowpilot/orbit-notebook` in the macOS Notebook's **Dependencies** panel to install the registry release. For a source checkout, choose `packages/orbit-notebook` with **Install Local Package**. It uses the enclosing Orbit checkout. An installed Orbit release can recommend the companion in Dependencies, including when Orbit arrived through another package. The **orbit-notebook** palette tab contains **HTTP Server** and **HTTP Server Board**.

HTTP Server belongs to Services. Choose a port and optionally an exported function that returns `orbit.Routes` in the Object Inspector. Port 0 lets Orbit choose an available loopback port. Save the board and choose **Start Board**. The service shows the URL and a **Copy Token** action for its current session.

The built-in routes are **GET /health** and **POST /reading**. Configure an input in the Object Inspector to accept a JSON value for that input. Both routes require the service's Bearer token. HTTP Server Board has its own string input, controller and service. Instances of the board show independent results and receive separate tokens and ports.

Choose **Stop Board** to stop the listener and its child services. This package runs on the Mac hosting the book.
