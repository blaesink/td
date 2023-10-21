from contextlib import nullcontext
from td import Todo, Add, Delete, Manager, read_file
import pytest


@pytest.fixture
def fake_todo_file():
    return """- Make bread
    - Get a haircut +Personal +Wedding"""


@pytest.fixture
def fake_todo_list() -> list[Todo]:
    return [Todo("Fix car +Roadtrip"), Todo("File taxes")]


def test_make_todo_from_line():
    td1 = "- Make a sandwich +Personal"

    actual = Todo.from_line(td1)

    assert actual.tags == ["Personal"]
    assert actual.group == "-"


def test_read_file(fake_todo_file, mocker):
    mock_file = mocker.patch("builtins.open")
    mock_file.return_value.__enter__.return_value.readlines.return_value = (
        fake_todo_file.split("\n")
    )

    actual = read_file("bad_path")
    assert len(actual) == 2
    assert actual[0].tags == []
    assert actual[1].tags == ["Personal", "Wedding"]


def test_manager_hash(mocker):
    fake_todo = Todo("File taxes")
    mock_desc = mocker.patch.object(fake_todo, "description")
    mock_desc.__hash__.return_value = 6642019057057375397

    actual = Manager.generate_hash(fake_todo)
    assert actual == "cmbkstlrtdsorepdofji"


def test_manager_from_items(fake_todo_list):
    with nullcontext():  # does not raise
        m = Manager(*fake_todo_list)
        assert len(m.items) == 2


def test_simulate_add_todo():
    """Pretend we get a command from stdin"""
    m = Manager()
    cmd = 'add "Buy Watermelon"'

    actual = m.eval(cmd)
    assert isinstance(actual, Add)
    assert len(m.items) > 0

    cmd = f"rm {actual.val}"
    assert isinstance(m.eval(cmd), Delete)
    assert len(m.items) == 0


def test_add_duplicate_todo():
    t = Todo.from_line("Take out trash")
    m = Manager()

    m.add_todo(t)

    with pytest.raises(KeyError):
        m.add_todo(Todo.from_line("Take out trash"))
