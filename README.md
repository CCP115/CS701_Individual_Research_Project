# CS701_Individual_Research_Project
A digital design project, focused on creating an ASIC processor that can store to local memory, perform convolution, perform correlation, and do a direct passthrough of supplied values.

The individual component of the project took place over a timespan of roughly 3-4 weeks, and was a sub component of a larger 12 week project.
The individual component required each student to have a unique functionality inside, with some justificaiton to the chosen algorithm/kernel operation.
I chose to do Convolution/Correlation due to its ubiquity in signal processing and machine learning applications.

The bulk of the work was designing a self contained processor that was able to interface to an external Network on a Chip (NoC), and was able to stream values in
from this NoC, save them, and perform operations on them.

The pdf file is a report that covers the functionality and implementation of the designed ASIC processor. The report also goes over potential improvements and different approaches
that could have been taken.

All design and implementation was done in VHDL, simulation was done using Modelsim, and compilation for resource usage and timing checking was done using Quartus.
