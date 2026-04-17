---
name: create-code-map
description: Maps out implementation for engineers to understand how the codebase works
---

For the **target scope**, use only user-indicated files, directories, or a feature area. If the scope is unclear, ask before mapping.

Within that scope, map how the pieces connect and how the implementation works. **Deliver:**

1. A high-level explanation of the code and its functionality.
2. A Mermaid diagram showing how **components** connect. Treat a component as a class or other discrete unit of functionality (e.g. lambda handlers, SwiftUI views/view models); the usual boundary is one file. Show component names, a short description of each, and how they connect. Cover all components in the target scope; if there are independent clusters, use a separate diagram for each cluster.
3. How the code is tested: briefly describe existing tests for the target scope and note plausible gaps if any.

**Output:** Markdown file saved in the current working directory suitable for Typora and for sharing with another engineer.
