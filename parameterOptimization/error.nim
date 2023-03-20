import math

func error*(outcome, estimate: float): float =
    (outcome - estimate)^2

func errorDerivative*(outcome, estimate: float): float =
    2.0 * (outcome - estimate)