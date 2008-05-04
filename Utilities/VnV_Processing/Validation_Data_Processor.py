import csv
from re import *
from pyx import *

### Set Global Variables

data_directory = "../../Validation/"
output_directory = "../../Manuals/FDS_5_Validation_Guide/FIGURES/"
config_file_name = "Validation_Data_Config_File.csv"

scatter_data_dict = {}
combined_scatter_data = {}

### Define Functions

def extract_config_data(config_file):
    print "*** Extracting Configuration Data and Building Dictionaries ***"
    
    # Collect Data from Config File
    groups_dict = {}
    quantities_dict = {}
    data_dict = {}
    keyed_groups = {}
    keyed_quantities = {}
    keyed_data = {}
    quantity_counter = 0
    data_counter = 0
    group_counter = 0
    skip_counter = 0
    
    #Create File Object
    try:
        fh = file(config_file, 'U')
    except:
	    print"!!! The Config File "+config_file_name+" does not exist or the path defined in the script is incorrect. !!!"
	    exit()
	
    #Read file with csv module.
    data_array = csv.reader(fh)
    #Convert into List object
    config_lists = [list(sublist) for sublist in data_array]
    print str(len(config_lists))+" lines read in from "+config_file_name+"\n"
    
    #Build Quantity and Data Dictionaries, with values keyed by config column name.
    for list_item in config_lists:
        if list_item[0] == 'g':
            if group_counter < 1:
                group_header = list_item[2:]
            else:
                if group_counter >= 1:
                    for x in range(len(group_header)):
                        keyed_groups[group_header[x]] = list_item[x+2]
                    groups_dict[int(list_item[1])] = keyed_groups
                    keyed_groups = {}
            group_counter += 1
            #print "This is group line #"+str(group_counter)+"."
        elif list_item[0] == 'q':
            if quantity_counter < 1:
                quantity_header = list_item[2:]
            if quantity_counter >= 1:
                for x in range(len(quantity_header)):
                    keyed_quantities[quantity_header[x]] = list_item[x+2]
                #print "List item 1:",int(list_item[1])
                quantities_dict[int(list_item[1])] = keyed_quantities
                keyed_quantities = {}
            quantity_counter += 1
        elif list_item[0] == 'd':
            if data_counter < quantity_counter:
                data_counter = quantity_counter - 1
                data_header = list_item[1:]
            if data_counter >= quantity_counter:
                for x in range(len(data_header)):
                    keyed_data[data_header[x].strip()] = list_item[x+1]
                data_key_name = keyed_data['Quantity'].strip()+"~"+keyed_data['Group'].strip()+"~"+keyed_data['Dataname'].strip()+"~"+keyed_data['Exp_Col_Name'].strip()
                print "Key Name:", data_key_name
                data_dict[data_key_name] = keyed_data
                #print data_dict[data_key_name]
                keyed_data = {}
            data_counter += 1
        else:
            skip_counter = skip_counter + 1
            #print """No g, d or q, skip row."""
            
    print "There were "+str(skip_counter)+" lines skipped, out of the "+str(len(config_lists))+" lines read in."
    
    # Return a single list object containing the dictionaries.
    #print groups_dict
    #print quantities_dict
    #print data_dict
    return [groups_dict,quantities_dict,data_dict]

def find_start_stop_index(data_dict,col_name,start_time_data,stop_time_data,start_time_comp,stop_time_comp):
    #This function is used to find index numbers for start and stop points in plotting and min-max values.
    rowcounter1 = 0
    for time_value1 in data_dict[col_name]:
        if time_value1 >= (float(start_time_data)*60):
            #print "Time Starts at row #:", str(rowcounter1)
            #print "With a value of:", str(time_value1)
            time_start_index = rowcounter1
            break                
        rowcounter1 += 1
    rowcounter2 = 0
    for time_value2 in data_dict[col_name]:
        if float(data_dict[col_name][(len(data_dict[col_name])-1)]) < (float(stop_time_data)*60):
            #print "Specified end of plot time is greater than end of time in the data set. \nUsing last value in the time column.\n"
            #print "Time used is: "+str(float(data_dict[col_name][(len(data_dict[col_name])-1)]))+"\n"
            time_end_index = (len(data_dict[col_name])-1)
            break
        else:
            row_number2 = (rowcounter2 - 1)
            #print "Time Ends at row #: "+str(row_number2)
            #print "With a value of: "+str(data_dict[col_name][row_number2])
            time_end_index = row_number2
            break
        if time_value2 < (float(stop_time_data)*60):
            rowcounter2 += 1
    rowcounter3 = 0
    for time_value3 in data_dict[col_name]:
        if time_value3 >= (float(start_time_comp)*60):
            #print "Comparison Time Starts at row #:", str(rowcounter3)
            #print "With a value of:", str(time_value3)
            minmax_start_index = rowcounter3
            break
        rowcounter3 += 1  
    rowcounter4 = 0
    for time_value4 in data_dict[col_name]:
        if float(data_dict[col_name][(len(data_dict[col_name])-1)]) < (float(stop_time_comp)*60):
            #print "Specified end of comparison time is greater than end of time in the data set. \nUsing last value in the time column."
            #print "Time used is: "+str(float(data_dict[col_name][(len(data_dict[col_name])-1)]))+"\n"
            minmax_end_index = (len(data_dict[col_name])-1)
            break
        if time_value4 < (float(stop_time_data)*60):
            rowcounter4 += 1
        else:
            row_number4 = (rowcounter4 - 1)
            #print "Comparison Time Ends at row #: "+str(row_number4)
            #print "With a value of: "+str(data_dict[col_name][row_number4])
            minmax_end_index = row_number4
            break
    return (time_start_index, time_end_index, minmax_start_index, minmax_end_index)

def extract_comp_data(comp_file_info):
    ## Read in d line dict from config file and Process data from source .csv files.
    
    exp_data = []
    mod_data = []
    exp_data_dict = {}
    mod_data_dict = {}
    exp_scatter_data_labels = []
    mod_scatter_data_labels = []
    
    #List of variables from configuration file column names.
    
    exp_data_filename = comp_file_info['Exp_Filename'] #String of filename
    exp_column_name_row_index = int(comp_file_info['Exp_Col_Name_Row'])-1 #Experimental Data Column Name Row Number
    exp_data_row_index = int(comp_file_info['Exp_Data_Row'])-1 #Experimental Data Starting Row Number
    exp_start_time_data_val = comp_file_info['Exp_Start_(min.)'] #String in minutes to start exp plot data
    exp_stop_time_data_val = comp_file_info['Exp_End_(min.)'] #String in minutes to stop exp plot data
    exp_start_time_comp_val = comp_file_info['Exp_Comp_Start_(min.)'] #String in minutes to start exp compare data
    exp_stop_time_comp_val = comp_file_info['Exp_Comp_End_(min.)'] #String in minutes to start exp compare data
    exp_initial_value = comp_file_info['Exp_Intitial_Value'] #Initial Value for Quantity
    exp_column_name_value = comp_file_info['Exp_Col_Name'].strip() #Experimental Data Column Name
        
    mod_data_filename = comp_file_info['Mod_Filename'] #String of filename
    mod_column_name_row_index = int(comp_file_info['Mod_Col_Name_Row'])-1 #Modeling Data Column Name Row Number
    mod_data_row_index = int(comp_file_info['Mod_Data_Row'])-1 #Modeling Data Starting Row Number
    mod_start_time_data_val = comp_file_info['Mod_Start_(min.)'] #String in minutes to start mod plot data
    mod_stop_time_data_val = comp_file_info['Mod_End_(min.)']  #String in minutes to stop mod plot data
    mod_start_time_comp_val = comp_file_info['Mod_Comp_Start_(min.)'] #String in minutes to start mod compare data
    mod_stop_time_comp_val = comp_file_info['Mod_Comp_End_(min.)']  #String in minutes to start mod compare data
    mod_initial_value = comp_file_info['Mod_Intitial_Value']       #Initial Value for Quantity
    mod_column_name_value = comp_file_info['Mod_Col_Name'].strip() #Modeling Data Column Name
    
    # Create Scatter Data Labels for the comparison results.
    
    if exp_column_name_value[0] == '[':
        print "Exp Column Name List Detected"
        exp_compound_col_names = eval(exp_column_name_value)
        for name in exp_compound_col_names:
            print "Exp Sub-Column Name:", name
            exp_scatter_data_labels.append(comp_file_info['Quantity']+"~"+comp_file_info['Group']+"~"+comp_file_info['Dataname']+"~"+name)
    else:
        print "Single Exp. Column Name:", exp_column_name_value
        exp_scatter_data_labels.append(comp_file_info['Quantity']+"~"+comp_file_info['Group']+"~"+comp_file_info['Dataname']+"~"+exp_column_name_value)        
    
    if mod_column_name_value[0] == '[':
        print "Mod Column Name List Detected"
        mod_compound_col_names = eval(mod_column_name_value)
        for name in mod_compound_col_names:
            print "Mod Sub-Column Name:", name
            mod_scatter_data_labels.append(comp_file_info['Quantity']+"~"+comp_file_info['Group']+"~"+comp_file_info['Dataname']+"~"+name)
    else:
        print "Single Mod. Column Name:", mod_column_name_value
        mod_scatter_data_labels.append(comp_file_info['Quantity']+"~"+comp_file_info['Group']+"~"+comp_file_info['Dataname']+"~"+mod_column_name_value)
    
    #print "Exp Data Labels:\n", exp_scatter_data_labels
    #print "Mod Data Labels:\n", mod_scatter_data_labels
    
    combined_scatter_data = [exp_scatter_data_labels,mod_scatter_data_labels]
    #print "Combined Scatter Data:",combined_scatter_data
    
    min_max = comp_file_info['max/min'] #String indicating if min or max value is required.
    
    group_value = int(comp_file_info['Group'])
    
    try:
        exp_file_object = open(data_directory+exp_data_filename, "U")
    except:
        print "!!! Experimental "+exp_data_filename+" Data File will not open. !!!"
        exit()
        
    try:
        mod_file_object = open(data_directory+mod_data_filename, "U")
    except:
        print "!!! Modeling "+mod_data_filename+" Data File will not open. !!!"
        exit()
    
    ## Start File Processing
    
    #Read in experimental data and flip lists from rows to columns.
    print "Reading in:", exp_data_filename
    exp_data_cols = zip(*csv.reader(exp_file_object))
    #Convert tuples to lists.
    exp_data_list = [list(sublist) for sublist in exp_data_cols]
    #Pull the Time column name out and strip whitespace. Assumes that Time is in first column.
    exp_time_col_name = exp_data_list[0][exp_column_name_row_index].strip()
    
    #Build Experimental Data Dictionary. 
    #Catch errors if conversion of data from string to float fails.
    for exp_list in exp_data_list:
        # try:
        temp_list = []
        for x in exp_list[exp_data_row_index:]:
            if x == 'Null' or x == '':
                list_value = 'Null'
            else:
                list_value = float(x)
            temp_list.append(list_value)
        exp_data_dict[exp_list[exp_column_name_row_index].strip()] = temp_list
        # except:
        #     print "!!! Exp Data Conversion in Column Name "+exp_list[exp_column_name_row_index].strip()+". !!!"
        #     exit()
    
    #Read in model data and flip lists from rows to columns.
    print "Reading in:", mod_data_filename
    mod_data_cols = zip(*csv.reader(mod_file_object))
    #Convert tuples to lists.
    mod_data_list = [list(sublist) for sublist in mod_data_cols]
    #Pull the Time column name out and strip whitespace from ends of string.
    mod_time_col_name = mod_data_list[0][mod_column_name_row_index].strip()
    
    #Build Prediction/Model Data Dictionary
    #Catch errors if conversion of data from string to float fails.
    for mod_list in mod_data_list:
        try:
            temp_list = []
            for x in mod_list[mod_data_row_index:]:
                if x == 'Null' or x =='':
                    list_value = 'Null'
                else:
                    list_value = float(x)
                temp_list.append(list_value)
            mod_data_dict[mod_list[mod_column_name_row_index].strip()] = temp_list
        except:
            print "!!! Mod Data Conversion in Column Name "+mod_list[mod_column_name_row_index].strip()+". !!!"
            exit()
    
    # Assuming that all column time ranges are the same.  Passing in the first Column Name.
    exp_comp_ranges = find_start_stop_index(exp_data_dict,exp_time_col_name,exp_start_time_data_val,exp_stop_time_data_val,exp_start_time_comp_val,exp_stop_time_comp_val)
    mod_comp_ranges = find_start_stop_index(mod_data_dict,mod_time_col_name,mod_start_time_data_val,mod_stop_time_data_val,mod_start_time_comp_val,mod_stop_time_comp_val)
    #print exp_comp_ranges
    #print mod_comp_ranges
    
    #### Begin Column specific operations.
    scatter_counter = 0
    
    for scatter_label in combined_scatter_data[0]:
        
        exp_label_temp = split("~",combined_scatter_data[0][scatter_counter])
        mod_label_temp = split("~",combined_scatter_data[1][scatter_counter])
        
        ##Find max or min values.
        exp_data_values_comp = exp_data_dict[exp_label_temp[3]][exp_comp_ranges[2]:exp_comp_ranges[3]]
        mod_data_values_comp = mod_data_dict[mod_label_temp[3]][mod_comp_ranges[2]:mod_comp_ranges[3]]
        
        # This allows the d line Quantity value to be set to 0 when either model or experimental data is missing.
        if comp_file_info['Quantity'] == str(0):
            print "Quantity set to 0, no comparison made."
        else:
            if  min_max == 'max':
                print "*** Rise Computed ***"
                temp_exp_data_values = [x for x in exp_data_values_comp if x != 'Null']
                exp_rise_value = max(temp_exp_data_values) - float(exp_initial_value)
                temp_mod_data_values = [x for x in mod_data_values_comp if x != 'Null']
                mod_rise_value = max(temp_mod_data_values) - float(mod_initial_value)
                print "Experimental Initial Value is:", exp_initial_value
                print "Experimental Rise Value is:", exp_rise_value
                print "Model Initial Value is:", mod_initial_value
                print "Model Rise Value is:", mod_rise_value
                print "\n*** Computing Relative Difference ***"
                try:
                    relative_difference = ((mod_rise_value-exp_rise_value)/exp_rise_value)
                    print "Relative Difference is:", relative_difference
                    #Append Rise Values to Global Scatter Data Dictionary.
                    scatter_data_dict[combined_scatter_data[0][scatter_counter]] = [exp_rise_value,mod_rise_value,relative_difference]
                except:
                    print "!!! Computation of relative_difference failed. !!!\nCheck source data for columns listed above."
                    exit()
            elif min_max == 'min':
                print "*** Drop Computed ***"
                temp_exp_data_values = [x for x in exp_data_values_comp if x != 'Null']
                exp_drop_value = float(temp_exp_data_values) - min(exp_data_values_comp)
                temp_mod_data_values = [x for x in mod_data_values_comp if x != 'Null']
                mod_drop_value = float(temp_mod_data_values) - min(mod_data_values_comp)
                print "Experimental Initial Value is:", exp_initial_value
                print "Experimental Drop Value is:", exp_drop_value
                print "Model Initial Value is:", mod_initial_value
                print "Model Drop Value is:", mod_drop_value
                print "\n*** Computing Relative Difference ***"
                try:
                    relative_difference = ((mod_drop_value-exp_drop_value)/exp_drop_value)
                    print "Relative Difference is:", relative_difference
                    #Append Drop Values to Global Scatter Data Dictionary.
                    scatter_data_dict[combined_scatter_data[0][scatter_counter]] = [exp_drop_value,mod_drop_value,relative_difference]
                except:
                    print "!!! Computation of relative_difference failed. !!!\nCheck source data for columns listed above."
                    exit()
            else:
                print "!!! Min or Max is undefined in the input file. !!!"
                exit()
                
        #Create data lists based on specified ranges
        exp_data_seconds = zip(exp_data_dict[exp_time_col_name][exp_comp_ranges[0]:exp_comp_ranges[1]], exp_data_dict[exp_label_temp[3]][exp_comp_ranges[0]:exp_comp_ranges[1]])
        #print exp_data_seconds
        
        mod_data_seconds = zip(mod_data_dict[mod_time_col_name][mod_comp_ranges[0]:mod_comp_ranges[1]], mod_data_dict[mod_label_temp[3]][mod_comp_ranges[0]:mod_comp_ranges[1]])
        #print mod_data_seconds
        
        #Convert time to minutes from seconds.
        exp_data.append([[x[0] / 60, x[1]] for x in exp_data_seconds])
        #print exp_data
        mod_data.append([[x[0] / 60, x[1]] for x in mod_data_seconds])
        #print mod_data
        scatter_counter =+ 1
        
    # Close files
    exp_file_object.close()
    mod_file_object.close()
    
    return [exp_data,mod_data]

def comparison_plot(plot_data,exp_data,mod_data):
    #plot_data is a list of values from the 'd' row of the config file being processed.
    
    # Variables for plot.
    plot_title = plot_data['Plot_Title']
    #print plot_title
    x_title = plot_data['X_Title']
    y_title = plot_data['Y_Title']   
    min_x = float(plot_data['Min_X'])
    max_x = float(plot_data['Max_X'])
    min_y = float(plot_data['Min_Y'])
    max_y = float(plot_data['Max_Y'])
    title_quadrant = int(plot_data['Title_Quadrant'])
    key_pos = plot_data['Key_Position']
    key_dist = 0.2*unit.v_cm
    plot_width = int(plot_data['Plot_Width(cm)'])
    
    #Create filename from fields in input file record.
    plot_file_name = plot_data["Plot_Filename"]
    
    # Determine the location for the key, alignment based on key_quadrant setting.
    # Replace quad code with actual position letters
    if key_pos == "tl" or "tc" or "tr" or "ml" or "mc" or "mr" or "bl" or "bc" or "br":
        ()
        #print "Key Position =", key_pos
    else:
        print "The key position was not specified./nUsing the default bottom right position."
        key_pos = "br"
    
    #Begin Plotting
    # Initialize graph object
    g = graph.graphxy(width=plot_width, ratio=4./3, key=graph.key.key(pos=key_pos, dist=key_dist), 
                        x=graph.axis.linear(title=x_title, min=min_x, max=max_x), 
                        y=graph.axis.linear(title=y_title, min=min_y, max=max_y))
    
    # Create line styles that have predetermined color order for each pair in series.  
    # All Experimental data is plotted with solid lines while Model data is dotted.
    expPlotStyle = graph.style.line(lineattrs=[attr.changelist([color.cmyk.Black, color.cmyk.Red, color.cmyk.Green, color.cmyk.Blue]), style.linestyle.solid, style.linewidth(0.06*unit.w_cm)])
    modPlotStyle = graph.style.line(lineattrs=[attr.changelist([color.cmyk.Black, color.cmyk.Red, color.cmyk.Green, color.cmyk.Blue]), style.linestyle.dotted, style.linewidth(0.06*unit.w_cm)])
    
    # Loop strcuture to process compound colum names in d line.
    if len(exp_data) > 1 :
        #Set plot legend key text.
        exp_key_list = eval(plot_data['Exp_Key'])
        mod_key_list = eval(plot_data['Mod_Key'])
        exp_plot_counter = 0
        mod_plot_counter = 0
        
        # Loop through and plot Experimental data
        for exp_data_item in exp_data:
            g.plot(graph.data.points(exp_data_item, title=exp_key_list[exp_plot_counter], x=1, y=2),
                  [expPlotStyle])
            exp_plot_counter =+ 1
            
        # Loop through and plot Experimental data
        for mod_data_item in mod_data:
            g.plot(graph.data.points(mod_data_item, title=mod_key_list[mod_plot_counter], x=1, y=2),
                  [modPlotStyle])
            mod_plot_counter =+ 1
    else:
        #Set plot legend key text.
        exp_key = plot_data['Exp_Key']
        mod_key = plot_data['Mod_Key']
        
        # Plot Experimental data
        g.plot(graph.data.points(exp_data[0], title=exp_key, x=1, y=2),
            [graph.style.line([color.rgb.black, style.linewidth(0.06*unit.w_cm), style.linestyle.solid])])
        # Plot Predicted/Model data
        g.plot(graph.data.points(mod_data[0], title=mod_key, x=1, y=2),
            [graph.style.line([color.rgb.black, style.linewidth(0.06*unit.w_cm), style.linestyle.dotted])])
    
    # Now plot the Title text, alignment based on title quadrant setting.
    if title_quadrant == 1:
        g.text(0.1, g.height - 0.2, plot_title, [text.halign.left, text.valign.top, text.size.small])
    elif title_quadrant == 2:
        g.text(g.width-0.1, g.height - 0.2, plot_title, [text.halign.right, text.valign.top, text.size.normalsize])
    elif title_quadrant == 3:
        g.text(0.1, 0.2, plot_title, [text.halign.left, text.valign.bottom, text.size.normalsize])
    elif title_quadrant == 4:
        g.text(g.width-0.1, 0.2, plot_title, [text.halign.right, text.valign.bottom, text.size.normalsize])
    else:
        print "A quadrant for the title location was not specified./nUsing the default top left quadrant."
        g.text(0.1, g.height - 0.2, plot_title, [text.halign.left, text.valign.top, text.size.small])
        
    # Write the output
    plot_file_path = output_directory+plot_file_name
    g.writePDFfile(plot_file_path)
    print "\n*** Comparison Plot to: ***\n", plot_file_path+".PDF"

def scatter_plot(group_info,scatter_info,data_set):
    #data_set is a dictionary keyed by quantity, containing lists of groups and X and Y data points.
    #print "Group Info:", group_info
    
    for quantity_number in scatter_info:
        #print "Dataset for quantity number "+str(quantity_number)+": ", data_set[quantity_number]
        
        if data_set[quantity_number] == []:
            print "No Scatter Plot Data in Quantity "+str(quantity_number)+" Dataset.\n"
        else:
            print "Scatter Plot Data for Quantity "+str(quantity_number)+" Dataset."
            # Set variables for Plot extracted from the first group of lines in config file starting with 'q'.
            
            # Variables for plot.
            plot_title = scatter_info[int(quantity_number)]['Scatter_Plot_Title']
            print plot_title
            
            x_title = scatter_info[int(quantity_number)]['X_Title']
            y_title = scatter_info[int(quantity_number)]['Y_Title']
            min_x = float(scatter_info[int(quantity_number)]['Plot_Min'])
            #print min_x
            max_x = float(scatter_info[int(quantity_number)]['Plot_Max'])
            #print max_x
            min_y = float(scatter_info[int(quantity_number)]['Plot_Min'])
            max_y = float(scatter_info[int(quantity_number)]['Plot_Max'])
            percent_error = float(scatter_info[int(quantity_number)]['%error'])
            title_quadrant = int(scatter_info[int(quantity_number)]['Title_Quadrant'])
            key_pos = scatter_info[int(quantity_number)]['Key_Position']
            key_dist = 0.2*unit.v_cm
            plot_width = int(scatter_info[int(quantity_number)]['Plot_Width(cm)'])
            
            #Create filename from fields in input file record.
            plot_file_name = scatter_info[int(quantity_number)]['Plot_Filename']
            #print plot_file_name
            
            # Determine the location for the key, alignment based on key_quadrant setting.
            if key_pos == "tl" or "tc" or "tr" or "ml" or "mc" or "mr" or "bl" or "bc" or "br":
                ()
                #print "Key Position =", key_pos
            else:
                print "The key position was not specified.\nUsing the default bottom right position."
                key_pos = "br"
            
            #Begin Plotting
            #print exp_data
            #print mod_data
            # Initialize graph object
            g = graph.graphxy(width=plot_width, ratio=1/1, key=graph.key.key(pos=key_pos, dist=key_dist), 
                                x=graph.axis.linear(title=x_title, min=min_x, max=max_x), 
                                y=graph.axis.linear(title=y_title, min=min_y, max=max_y))
            
            #Plot Midline and Error bounds lines.
            errorLineCenterPoints = [[min_x,min_y],[max_x,max_y]]
            
            if min_x < 0:
                #print errorLineCenterPoints
                lower_bound = ((min_y)+((min_y)*(percent_error / 100)))
                #print "Lower Bound:", lower_bound
                errorLineLowerPoints = [[min_x,lower_bound],[max_x,max_y]]
                #print "Lower Error Line Points:", errorLineLowerPoints
                upper_bound = ((min_y)-((min_y)*(percent_error/100)))
                #print "Upper Bound:", 
                errorLineUpperPoints = [[min_x,upper_bound],[max_x,max_y]]
                #print "Upper Error Line Points:", errorLineUpperPoints
            else:
                #print errorLineCenterPoints
                lower_bound = max_y - max_y * percent_error / 100
                #print lower_bound
                errorLineLowerPoints = [[min_x,min_y],[max_x,lower_bound]]
                #print errorLineLowerPoints
                upper_bound = max_y + max_y * percent_error / 100.0
                #print upper_bound
                errorLineUpperPoints = [[min_x,min_y],[max_x,upper_bound]]
                #print errorLineUpperPoints
            
            g.plot(graph.data.points(errorLineCenterPoints, title=None, x=1, y=2),
                    [graph.style.line([style.linewidth.Thin, style.linestyle.solid])])
                    
            if percent_error == 0:
                print "No Error Bars Drawn"
            else:
                g.plot(graph.data.points(errorLineLowerPoints, title=None, x=1, y=2),
                        [graph.style.line([style.linewidth.Thin, style.linestyle.dashed])])
                    
                g.plot(graph.data.points(errorLineUpperPoints, title=None, x=1, y=2),
                        [graph.style.line([style.linewidth.Thin, style.linestyle.dashed])])
            
            #One point at a time added to plot from each data set.
            # Iterate over items in scatter data dictionary key for items that are not [].
            # Append data sets to scatter_plot_data_list
            # colors for symbols are from http://pyx.sourceforge.net/manual/colorname.html
            
            scatter_plot_data_list = []
            
            grouped_data = {}
            grouped_data_list = range(len(group_quantity_data_dicts[0])+1)
            #print "Grouped Data List:", grouped_data_list
            
            #print "DataSet for Quantity "+str(quantity_number)+":", data_set[quantity_number]
            if len(data_set[quantity_number]) > 1:
                #print "Grouped Scatter Data:"
                #print data_set[quantity_number]
                for arr_temp in grouped_data_list:
                    grouped_data_list[arr_temp] = []
                for data_set_item in data_set[quantity_number]:
                    #print data_set_item
                    #print "Data for group "+data_set_item[0]+":", data_set_item[1]
                    grouped_data_list[int(data_set_item[0])].append(data_set_item[1])
                #print "Grouped data list:", grouped_data_list
                                
                group_counter = 0
                for j in grouped_data_list:
                    #print "J =", j
                    if j != []:
                        #print group_counter
                        
                        # Pull group symbol specifications from config file.
                        config_group_symbol = group_info[group_counter]["Symbol"]
                        #print config_group_symbol
                        group_symbol = "graph.style.symbol."+config_group_symbol
                        #print group_symbol
                        
                        config_group_symbol_color = group_info[group_counter]["Color"]
                        #print config_group_symbol_color
                        #group_color = "color.rgb."+config_group_symbol_color
                        
                        config_group_symbol_filled = group_info[group_counter]["Filled"]
                        #print config_group_symbol_filled
                        
                        if config_group_symbol_filled == 'yes':
                            fillstyle = "deco.filled([color.cmyk."+config_group_symbol_color+"])"
                        else:
                            fillstyle = "deco.stroked([color.cmyk."+config_group_symbol_color+"])"
                        #print group_symbol, fillstyle     
                        
                        #Create temporary symbol style.
                        tempstyle = "graph.style.symbol("+group_symbol+", size=0.1*unit.v_cm, symbolattrs=["+fillstyle+"])"
                        #print "TempStyle:", tempstyle
                        
                        scatterpointstyle = eval(tempstyle)
                        
                        #print group_info[group_counter]["Group_Title"]
                        g.plot(graph.data.points(j, x=1, y=2, title=group_info[group_counter]["Group_Title"]), [scatterpointstyle])
                    else:
                        pass
                    group_counter = group_counter + 1
                    
            else:
                print "Non-Grouped Scatter Data:"
                #print data_set[quantity_number]
                scatter_plot_data = []
                scatter_plot_data.append(data_set[quantity_number][0][1])
                #print scatter_plot_data
                
            #print grouped_data_list
            
            # Now plot the Title text, alignment based on title quadrant setting.
            if title_quadrant == 1:
                g.text(0.1, g.height - 0.2, plot_title, [text.halign.left, text.valign.top, text.size.small])
            elif title_quadrant == 2:
                g.text(g.width-0.1, g.height - 0.2, plot_title, [text.halign.right, text.valign.top, text.size.small])
            elif title_quadrant == 3:
                g.text(0.1, 0.2, plot_title, [text.halign.left, text.valign.bottom, text.size.small])
            elif title_quadrant == 4:
                g.text(g.width-0.1, 0.2, plot_title, [text.halign.right, text.valign.bottom, text.size.small])
            else:
                print "A title location was not specified./nUsing the default top left quadrant."
                g.text(0.1, g.height - 0.2, plot_title, [text.halign.left, text.valign.top, text.size.small])
            
            #Make %error text on plot by error bars.
            # pos_percent_error = str(percent_error)+"%"
            # neg_percent_error = "-"+str(percent_error)+"%"
            # g.text(g.width - 0.4, g.height - 0.3, pos_percent_error, [text.halign.center, text.valign.middle, text.size.tiny])
            # g.text(g.width - 0.2, g.height - 0.4, neg_percent_error, [text.halign.center, text.valign.middle, text.size.tiny])
            
            # Write the output
            plot_file_path = output_directory+plot_file_name
            #print plot_file_path
            g.writePDFfile(plot_file_path)
            print "Scatter Plot to: \n", plot_file_path+".PDF\n"


### Start of Main Code
print "**** READING CONFIGURATION FILE ****"

##Get information from config file.
group_quantity_data_dicts = extract_config_data(config_file_name)
print "\nThere are "+str(len(group_quantity_data_dicts[0]))+" scatter data groups, (g lines).\n"
#print group_quantity_data_dicts[0]
print "There are "+str(len(group_quantity_data_dicts[1]))+" scatter data quantities to plot, (q lines).\n"
#print group_quantity_data_dicts[1]
print "There are "+str(len(group_quantity_data_dicts[2]))+" comparison data sets to plot, (d lines).\n"

## Create comparison plots
print "**** CREATING COMPARISON PLOTS ****"
d_count = 1
for data_record in group_quantity_data_dicts[2]:
    # Each d line, data_record, may contain compound column names from the config file.
    print "*** #"+str(d_count)+" of "+str(len(group_quantity_data_dicts[2]))+" comparison records. ***\n"
    # Extract relevant portions of comparison data as defined in config file.
    comp_data_to_plot = extract_comp_data(group_quantity_data_dicts[2][data_record])
    #print "Comparison Data to Plot:", comp_data_to_plot
    
    #Seperate experimental and model data lists.
    exp_plot_data = comp_data_to_plot[0]
    mod_plot_data = comp_data_to_plot[1]
    
    #print "Exp Plot Data:", exp_plot_data
    #print "Mod Plot Data:", mod_plot_data
    
    # Create plot for data_record.
    comparison_plot(group_quantity_data_dicts[2][data_record],exp_plot_data,mod_plot_data)
    d_count = d_count + 1
    print "\n"

## Create scatter plots
print "**** CREATING SCATTER PLOTS ****"
scatter_quantity = 1
scatter_group = 1
temp_scatter_data_list = []

#Grouping Scatter Data by Quantity
for scatter_plot_record in sorted(group_quantity_data_dicts[1]):
    #print "Scatter Plot:", scatter_plot_record
    #print "Quantity:", group_quantity_data_dicts[1][scatter_plot_record]['Comparison_Quantities']
        
    for scatter_data_key in sorted(scatter_data_dict):
        split_key = split("~",scatter_data_key)
        if split_key[0] == str(scatter_plot_record) and scatter_data_dict[scatter_data_key] != []:
            temp_scatter_data_list.append([split_key[1], scatter_data_dict[scatter_data_key][:2]])
        else:
            pass
    
    #print temp_scatter_data_list
    combined_scatter_data[scatter_quantity] = temp_scatter_data_list
    temp_scatter_data_list = []
    scatter_quantity = scatter_quantity + 1

# Plot Data
#print "Data to Scatter Plot:", combined_scatter_data
scatter_plot(group_quantity_data_dicts[0],group_quantity_data_dicts[1],combined_scatter_data)

## Write Summary Data to File.
#NRC Comparisons Output
# Output for each data set 
#*Exp Zero Val
#*Exp Peak Val
#*Peak Time Val
#*Mod Zero Val
#*Mod Peak Val
#*Peak Time Val
#*DeltaE
#*DeltaM
#*Rel Diff

print "Processing finished, thank you for your patience."