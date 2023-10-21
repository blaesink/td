from td import Todo
import pytest

from td.main import Add, Delete, Manager, read_file

@pytest.fixture
def fake_todo_file():
    return """- Make bread
    - Get a haircut +Personal +Wedding"""

@pytest.fixture
def fake_todo_list():
    return [
        Todo("Fix car +Roadtrip"),
        Todo("File taxes")
    ]

def test_make_todo_from_line():
    td1 = "- Make a sandwich +Personal"

    actual = Todo.from_line(td1)

    assert actual.tags == ["Personal"]
    assert actual.group == "-"

def test_read_file(fake_todo_file, mocker):
    mock_file = mocker.patch("builtins.open")
    mock_file.return_value.__enter__.return_value.readlines.return_value = fake_todo_file.split("\n")

    actual =read_file("bad_path")
    assert len(actual) == 2
    assert actual[0].tags == []
    assert actual[1].tags == ["Personal", "Wedding"]

def test_manager_hash():
    actual = Manager.generate_hash(Todo("File taxes"))
    assert actual is not None

    # assert idempotency
    assert actual == Manager.generate_hash(Todo("File taxes"))

def test_simulate_add_todo():
    """Pretend we get a command from stdin"""
    m = Manager()
    cmd = "add \"Buy Watermelon\""

    actual = m.eval(cmd)
    assert isinstance(actual, Add)
    assert len(m.items) > 0

    cmd = f"rm {actual.val}"
    assert isinstance(m.eval(cmd), Delete)
    assert len(m.items) == 0