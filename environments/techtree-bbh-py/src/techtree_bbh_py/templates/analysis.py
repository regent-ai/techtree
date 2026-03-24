# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "marimo>=0.13.0",
# ]
# ///
import marimo

app = marimo.App()


@app.cell
def _():
    import json
    from pathlib import Path

    workspace = Path(__file__).resolve().parent
    task = json.loads((workspace / "task.json").read_text(encoding="utf-8"))
    protocol = (workspace / "protocol.md").read_text(encoding="utf-8")
    rubric = json.loads((workspace / "rubric.json").read_text(encoding="utf-8"))
    return workspace, task, protocol, rubric


@app.cell
def _(mo, task, protocol):
    mo.md(
        f"""# {task["title"]}

## Hypothesis
{task["hypothesis"]}

## Protocol
{protocol}
"""
    )
    return


if __name__ == "__main__":
    app.run()
