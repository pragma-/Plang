# This Plang script demonstrates some useful constructions of arrays
# and maps.

# Basic Array
var array = ["red", "green", 1, 2]

print(array[1])    # prints green
print(array)       # prints [ "red", "green", 1, 2 ]
print(type(array)) # prints Array

# Basic Map
var map = {
    'name'   : "Grok",
    'health' : 200,
    'iq'     : 75
}

print(map['name'])   # prints Grok
print(map)           # prints { "name": "Grok", "health": 200, "iq": 75 }

# Array of anonymous Arrays
var arrays = [[1, 2], [3, 4], [5, 6]]

print(arrays[2][1]) # prints 6

# Map of anonymous Arrays:

var map_arrays = {
    'colors': [ "red", "green", "blue" ],
    'shapes': [ "triangle", "square", "circle" ],
     'sizes': [ "small", "average", "big" ],
}

print(map_arrays['colors'][1])  # prints green

# To add another anonymous Array to the Map:

map_arrays['pets'] = [ "cat", "dog", "hamster" ];

print(map_arrays) # this should print the map as expected

# Array of anonymous Maps

var array_maps = [
    {
        'name'   : "Grok the Caveman",
        'health' : 200,
        'iq'     : 75
    },
    {
        'name'   : "Merlin the Wizard",
        'health' : 100,
        'iq'     : 200
    },
    {
        'name'   : "Bob the Human",
        'health' : 75,
        'iq'     : 100,
    }
]

print(array_maps[1]['name'])  # prints Merlin the Wizard

# Map of anonymous Maps

var maps = {
    'caveman': {
        'health': 200,
        'iq'    : 75,
    },
    'wizard': {
        'health' : 100,
        'iq'     : 200,
    },
    'human': {
        'health' : 75,
        'iq'     : 100,
    }
}

print(maps['wizard']['iq'])  # prints 200

# To add another anonymous Map to the Map:

maps['dragon'] = { 'health': 500, 'iq': 150 }

print(maps)  # should print caveman, wizard, human and dragon as expected
