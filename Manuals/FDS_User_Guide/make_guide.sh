#!/bin/bash

# Add LaTeX search path; Paths are ':' separated
export TEXINPUTS=".:../LaTeX_Style_Files:"

clean_build=1

# Build FDS User Guide

gitrevision=`git describe --long --dirty`
echo "\\newcommand{\\gitrevision}{$gitrevision}" > ../Bibliography/gitrevision.tex

pdflatex -interaction nonstopmode FDS_User_Guide &> FDS_User_Guide.err
bibtex FDS_User_Guide &> FDS_User_Guide.err
pdflatex -interaction nonstopmode FDS_User_Guide &> FDS_User_Guide.err
pdflatex -interaction nonstopmode FDS_User_Guide &> FDS_User_Guide.err

# Scan and report any errors in the LaTeX build process
if [[ `grep -E "Error:|Fatal error|! LaTeX Error:|Paragraph ended before|Missing \\\$ inserted|Misplaced" -I FDS_User_Guide.err | grep -v "xpdf supports version 1.5"` == "" ]]
   then
      # Continue along
      :
   else
      echo "LaTeX errors detected:"
      grep -E "Error:|Fatal error|! LaTeX Error:|Paragraph ended before|Missing \\\$ inserted|Misplaced" -I FDS_User_Guide.err | grep -v "xpdf supports version 1.5"
      clean_build=0
fi

# Check for LaTeX warnings (undefined references or duplicate labels)
if [[ `grep -E "undefined|multiply defined|multiply-defined" -I FDS_User_Guide.err` == "" ]]
   then
      # Continue along
      :
   else
      echo "LaTeX warnings detected:"
      grep -E "undefined|multiply defined|multiply-defined" -I FDS_User_Guide.err
      clean_build=0
fi

if [[ $clean_build == 0 ]]
   then
      :
   else
      echo "FDS User Guide built successfully!"
fi    
