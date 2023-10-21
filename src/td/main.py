from typing import Optional, Self
from collections import OrderedDict

ALPHA = "abcdefghijklmnopqrstuvwxyz"

class Todo:
    """A Todo holds:

    - A `description` of what it is.
    - `tags` to organize it.
    - An optional `group` (single charater) to organize it with disparate tags (like a large project).
    """
    def __init__(self, description: str, *tags: str, group: Optional[str] = None):
        self.description = description
        self.tags = list(tags)
        self.group = group or "-"

    @classmethod
    def from_line(cls, line: str, /) -> Self:
        group = line[0]

        if (tags_start := line.find('+')) >= 0:
            description = line[2:tags_start-1]
            tags = line[tags_start:].split("+")[1:]

            # Clean whitespace
            for i, v in enumerate(tags):
                tags[i] = v.strip()

        else:
            description = line[2:]
            tags = []


        return Todo(description, *tags, group=group)

def read_file(fp: str, /) -> list[Todo]:
    with open(fp, "r") as f:
        return list(map(Todo.from_line, f.readlines()))

class Add:
    __slots__ = ("val",)

    def __init__(self, val: str, /):
        self.val = val

class Delete:
    __slots__ = ("val",)

    def __init__(self, val: Todo, /):
        self.val = val
   
Operation = Add | Delete

class Manager:
    def __init__(self, *todos: Todo):
        self.items: OrderedDict[str, Todo] = OrderedDict()
        for todo in todos:
            self.add_todo(todo)


    @staticmethod
    def generate_hash(todo: Todo) -> str:
        """Generate a letter hash from the input"""
        hsh = todo.description.__hash__()
        result = ""
        step = 1

        while hsh > 0:
            result += ALPHA[(hsh - step) % 26]
            step += 1
            hsh = hsh // step

        return result

    def add_todo(self, todo: Todo) -> str:
        hsh = self.generate_hash(todo)

        if self.items.get(hsh):
            raise KeyError(f"{hsh} already has an item!")
        self.items[hsh] = todo
        return hsh

    def remove_todo(self, hsh: str) -> Optional[Todo]:
        if not self.items.get(hsh):
            return None
        return self.items.pop(hsh)
        
    def eval(self, input: str, /) -> Operation:
        cmd, rest = input.split(" ", 1)

        match cmd:
            case "add" | "a":
                res = Add(self.add_todo(Todo.from_line(rest)))
            case "rm" | "del":
                maybe_todo = self.remove_todo(rest)
                if not maybe_todo:
                    raise ValueError(f"{rest} does not exist")
                res = Delete(maybe_todo)
            case _:
                raise ValueError(cmd)
            
        return res