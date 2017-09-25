class Colourize
  FG_NORMAL = -1
  BG_NORMAL = -1
  
  COLORS = [
    0,1,2,3,4,5,6,7,9
  ]
  
  def self.generate str, fcol=FG_NORMAL, bcol=BG_NORMAL, bold: false
    bcol = 9 if bcol == -1
    bcol = bcol + 40 if bcol <= 9
    
    fcol = 9 if fcol == -1
    fcol = fcol + 30 if fcol <= 9    
    
    bcol = 1 if bold
    
    "\e[#{fcol};#{bcol}m"+str+"\e[0m"  
  end
  
  def self.case str, truth, aset, bset = [-1,-1], &b
    if truth
      return generate str,*aset
    end
    
    generate str, *bset
  end
end

class String
  def colourize? truth, aset, bset=[-1,-1]
    Colourize.case self, truth, aset, bset
  end
  
  def colourize fg,bg=-1, bold: false
    Colourize.generate self,fg,bg, bold: bold
  end
end
