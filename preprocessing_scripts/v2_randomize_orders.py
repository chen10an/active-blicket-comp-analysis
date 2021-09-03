# Simple randomization of the order that participants are assigned to 6 experimental conditions (indexed by 0-5)

##
import numpy as np

##
# 40 participants in each condition
orders = ['0']*40 + ['1']*40 + ['2']*40 + ['3']*40 + ['4']*40 + ['5']*40
assert(len(orders) == 240)

##
# modern way of setting a reproducible numpy seed (https://towardsdatascience.com/stop-using-numpy-random-seed-581a9972805f)
rng = np.random.default_rng(0)

# random permutation of orders
rand_orders = rng.permutation(orders)

##
# print out for copy pasting into a somata config
print(rand_orders)
# out:
# 2, 5, 2, 5, 3, 5, 4, 4, 1, 5, 0, 1, 1, 3, 0, 4, 3, 0, 5, 0, 5, 2, 2, 5, 2, 5, 5, 5, 0, 4, 1, 0, 1, 1, 5, 2, 0, 1, 2, 3, 5, 3, 2, 3, 5, 3, 5, 0, 2, 5, 3, 2, 1, 4, 1, 5, 3, 2, 4, 4, 3, 4, 1, 2, 3, 1, 4, 5, 3, 3, 2, 0, 4, 2, 3, 0, 3, 4, 2, 2, 3, 2, 2, 0, 3, 2, 1, 5, 4, 4, 4, 1, 3, 1, 4, 5, 0, 2, 0, 2, 2, 3, 2, 0, 0, 3, 4, 3, 0, 1, 2, 1, 3, 0, 5, 1, 5, 2, 2, 5, 0, 3, 4, 5, 5, 1, 3, 0, 4, 0, 5, 5, 4, 2, 0, 4, 1, 4, 2, 3, 0, 3, 4, 0, 1, 0, 3, 0, 0, 2, 1, 3, 1, 3, 5, 0, 0, 4, 4, 2, 4, 0, 5, 2, 1, 3, 2, 0, 4, 4, 3, 3, 1, 4, 5, 2, 5, 3, 3, 3, 1, 5, 0, 5, 0, 4, 4, 4, 3, 4, 1, 1, 2, 1, 3, 0, 1, 2, 1, 5, 4, 5, 4, 2, 5, 1, 0, 0, 1, 1, 1, 0, 1, 4, 5, 5, 2, 0, 5, 2, 4, 1, 1, 0, 4, 5, 1, 2, 3, 3, 1, 3, 1, 4, 0, 4, 4, 0, 5, 2


