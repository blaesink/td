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
