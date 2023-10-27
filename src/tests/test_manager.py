import pytest
from contextlib import nullcontext
from td import Manager, Add, Delete, Todo, read_file


def test_manager_hash(mocker):
    fake_todo = Todo("File taxes")
    mock_desc = mocker.patch.object(fake_todo, "description")
    mock_desc.__hash__.return_value = 6642019057057375397

    actual = Manager.generate_hash(fake_todo)
    assert actual == "cmbkstlrtdsorepdofji"


def test_manager_hash_not_empty():
    fake_todo = Todo("File taxes")

    assert Manager.generate_hash(fake_todo) != ""


def test_manager_from_items(fake_todo_list):
    with nullcontext():  # does not raise
        m = Manager(*fake_todo_list)
    assert len(m.todos) == 2


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


def test_get_grouped_todos(mocker):
    todo_file = """A Find that weird bug +Dev
    A Tell Ray that the flux capacitor is broken +Job"""

    mock_file = mocker.patch("builtins.open")
    mock_file.return_value.__enter__.return_value.readlines.return_value = (
        todo_file.split("\n")
    )

    # just get the items from above
    td_list = read_file("fake_path")
    m = Manager(*td_list)

    actual = m.eval("ls &A")
    assert len(actual.val) == 2
