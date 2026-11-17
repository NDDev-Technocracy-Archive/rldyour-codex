from pathlib import Path

from scripts.validate_contract import source_command_directories


def test_prepared_pyright_stubs_are_not_adapter_commands(tmp_path: Path) -> None:
    (tmp_path / ".venv/lib/python3.13/site-packages/pyright/typeshed/channels/management/commands").mkdir(parents=True)
    assert source_command_directories(tmp_path) == []


def test_authored_command_surfaces_still_fail_even_with_an_environment_name(tmp_path: Path) -> None:
    direct = Path("plugins/rldyour-flow/commands")
    nested = Path("plugins/untrusted/.venv/commands")
    for name in (direct, nested):
        (tmp_path / name).mkdir(parents=True)
    assert set(source_command_directories(tmp_path)) == {direct, nested}
