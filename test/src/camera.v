module camera
	#(
	parameter  SLAVE_ADDR = 7'h3c         ,  //OV5640的器件地址7'h3c
	parameter  BIT_CTRL   = 1'b1          ,  //OV5640的字节地址为16位  0:8位 1:16位
	
	parameter  CLK_FREQ   = 26'd65_000_000,  //i2c_dri模块的驱动时钟频率 65MHz
	parameter  I2C_FREQ   = 18'd250_000   ,  //I2C的SCL时钟频率,不超过400KHz

    parameter CMOS_H_PIXEL = 24'd1024,//CMOS水平方向像素个数
    parameter CMOS_V_PIXEL = 24'd768  //CMOS垂直方向像素个数
    ) 
	(
	input                 clk_65m      	  ,
	input                 rst_n    		  ,  
	
	//与SDRAM的接口
	input                 sdram_init_done ,
	output                cmos_frame_valid,  //数据有效使能信号，//sdram_ctrl模块写使能
	output       [15:0]   cmos_frame_data ,   //有效数据        
	
	// 硬件输入
	input                 cam_pclk        ,  //cmos 数据像素时钟
	input                 cam_vsync       ,  //cmos 场同步信号
	input                 cam_href        ,  //cmos 行同步信号
	input        [7:0]    cam_data        ,  //cmos 数据 
	// 硬件输出
	output            	  cam_scl        	  ,      // I2C的SCL时钟信号
	inout                 cam_sda              // I2C的SDA信号
);

//parameter define
//parameter  SLAVE_ADDR = 7'h3c         ;  //OV5640的器件地址7'h3c
//parameter  BIT_CTRL   = 1'b1          ;  //OV5640的字节地址为16位  0:8位 1:16位
//parameter  CLK_FREQ   = 26'd65_000_000;  //i2c_dri模块的驱动时钟频率 65MHz
//parameter  I2C_FREQ   = 18'd250_000   ;  //I2C的SCL时钟频率,不超过400KHz
//parameter  CMOS_H_PIXEL = 24'd1024    ;  //CMOS水平方向像素个数,用于设置SDRAM缓存大小
//parameter  CMOS_V_PIXEL = 24'd768     ;  //CMOS垂直方向像素个数,用于设置SDRAM缓存大小

wire    [23:0]  i2c_data ;

assign  sys_init_done = sdram_init_done & cam_init_done;

//I2C配置模块
i2c_ov5640_rgb565_cfg 
   #(
     .CMOS_H_PIXEL      (CMOS_H_PIXEL),
     .CMOS_V_PIXEL      (CMOS_V_PIXEL)
    )   
   u_i2c_cfg(   
    .clk                (i2c_dri_clk),
    .rst_n              (rst_n),
    .i2c_done           (i2c_done),
    .i2c_exec           (i2c_exec),
    .i2c_data           (i2c_data),
    .init_done          (cam_init_done)
    );
	 
//I2C驱动模块
i2c_dri 
   #(
    .SLAVE_ADDR         (SLAVE_ADDR),       //参数传递
    .CLK_FREQ           (CLK_FREQ  ),              
    .I2C_FREQ           (I2C_FREQ  )                
    )   
   u_i2c_dri(   
    .clk                (clk_65m   ),
    .rst_n              (rst_n     ),   
        
    .i2c_exec           (i2c_exec  ),   
    .bit_ctrl           (BIT_CTRL  ),   
    .i2c_rh_wl          (1'b0),             //固定为0，只用到了IIC驱动的写操作   
    .i2c_addr           (i2c_data[23:8]),   
    .i2c_data_w         (i2c_data[7:0]),   
    .i2c_data_r         (),   
    .i2c_done           (i2c_done  ),   
    .scl                (cam_scl   ),   
    .sda                (cam_sda   ),   
        
    .dri_clk            (i2c_dri_clk)       //I2C操作时钟
);


//CMOS图像数据采集模块
cmos_capture_data u_cmos_capture_data(  //系统初始化完成之后再开始采集数据 
    .rst_n              (rst_n & sys_init_done), 		//只有当iic配置+SDRAM配置完成，才行
        
    .cam_pclk           (cam_pclk),
    .cam_vsync          (cam_vsync),
    .cam_href           (cam_href),
    .cam_data           (cam_data),
        
        
    .cmos_frame_vsync   (),
    .cmos_frame_href    (),
    .cmos_frame_valid   (cmos_frame_valid),       //数据有效使能信号
    .cmos_frame_data    (cmos_frame_data)      //有效数据 
    );

	 
endmodule